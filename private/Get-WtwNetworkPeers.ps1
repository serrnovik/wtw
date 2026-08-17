function Get-WtwTailscaleCommand {
    <#
    .SYNOPSIS
        Locate the tailscale CLI.
    .DESCRIPTION
        The macOS App Store build ships its CLI inside the bundle rather than on
        PATH, so a plain Get-Command misses it on exactly the machines most
        likely to have Tailscale installed.
    .OUTPUTS
        Path to the CLI, or $null.
    #>
    [CmdletBinding()]
    param()

    $onPath = Get-Command tailscale -ErrorAction SilentlyContinue
    if ($onPath -and $onPath.Source) { return $onPath.Source }

    $candidates = @(
        '/Applications/Tailscale.app/Contents/MacOS/Tailscale'
        '/usr/local/bin/tailscale'
        '/opt/homebrew/bin/tailscale'
        '/usr/bin/tailscale'
        "$env:ProgramFiles\Tailscale\tailscale.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    return $null
}

function ConvertFrom-WtwTailscaleOs {
    <#
    .SYNOPSIS
        Map a Tailscale OS string to a wtw platform, or $null if not hostable.
    .DESCRIPTION
        Tailscale reports the OS authoritatively, which is exactly what
        `--platform` needs — it drives remote path translation. Phones and
        tablets are in the tailnet too but cannot host a worktree or run pwsh,
        so they map to $null and get skipped rather than added and then failing.
    #>
    [CmdletBinding()]
    param([AllowNull()] [string] $Os)

    switch -Regex ($Os) {
        '^macOS$'   { return 'macos' }
        '^windows$' { return 'windows' }
        '^linux$'   { return 'linux' }
        default     { return $null }
    }
}

function Get-WtwTailscalePeers {
    <#
    .SYNOPSIS
        Machines in the tailnet, shaped for wtw host entries.
    .DESCRIPTION
        Reads `tailscale status --json`. The name comes from DNSName rather than
        HostName because mobile devices report HostName as "localhost" — DNSName
        is always the tailnet-unique name.

        Addresses are the MagicDNS FQDN first, then the tailnet IPv4. The FQDN is
        preferred over the bare short name because the short form only resolves
        when the tailnet search domain is configured, while the FQDN always does.
    .PARAMETER Raw
        Pre-parsed status object, for tests.
    .OUTPUTS
        @{ Name; DnsName; Platform; Addresses; Online; IsSelf; Os }
    #>
    [CmdletBinding()]
    param([AllowNull()] [object] $Raw)

    if ($null -eq $Raw) {
        $cli = Get-WtwTailscaleCommand
        if (-not $cli) { return , @() }
        $json = & $cli status --json 2>$null
        if (-not $json) { return , @() }
        try { $Raw = ($json -join "`n") | ConvertFrom-Json } catch { return , @() }
    }

    $nodes = @()
    $self = Get-WtwPropertyValue -Object $Raw -Name 'Self'
    if ($self) { $nodes += , @{ Node = $self; IsSelf = $true } }

    $peers = Get-WtwPropertyValue -Object $Raw -Name 'Peer'
    foreach ($key in (Get-WtwPropertyNames -Object $peers)) {
        $nodes += , @{ Node = (Get-WtwPropertyValue -Object $peers -Name $key); IsSelf = $false }
    }

    $result = @()
    foreach ($wrapped in $nodes) {
        $node = $wrapped.Node
        if (-not $node) { continue }

        $dns = [string](Get-WtwPropertyValue -Object $node -Name 'DNSName')
        $dns = $dns.TrimEnd('.')
        $name = if ($dns) { ($dns -split '\.')[0] } else { [string](Get-WtwPropertyValue -Object $node -Name 'HostName') }
        if (-not $name) { continue }

        $ips = @(Get-WtwPropertyValue -Object $node -Name 'TailscaleIPs' -DefaultValue @())
        $ipv4 = @($ips | Where-Object { $_ -and $_ -notmatch ':' }) | Select-Object -First 1

        $addresses = @()
        if ($dns) { $addresses += $dns }
        if ($ipv4) { $addresses += $ipv4 }

        $os = [string](Get-WtwPropertyValue -Object $node -Name 'OS')
        $result += @{
            Name      = $name.ToLowerInvariant()
            DnsName   = $dns
            Os        = $os
            Platform  = (ConvertFrom-WtwTailscaleOs -Os $os)
            Addresses = $addresses
            Online    = [bool](Get-WtwPropertyValue -Object $node -Name 'Online' -DefaultValue $false)
            IsSelf    = $wrapped.IsSelf
        }
    }

    return , @($result)
}

function Show-WtwZeroTierHint {
    <#
    .SYNOPSIS
        Explain the ZeroTier path, when ZeroTier is actually present.
    .DESCRIPTION
        Silent when ZeroTier is not installed — there is no point advertising a
        manual workaround for software the user does not run.
    #>
    [CmdletBinding()]
    param()

    # No @() wrapper: the function already returns `,@(...)`, and re-wrapping
    # nests the array so every element access reaches the wrapper instead.
    $networks = Get-WtwZeroTierNetworks
    if ($networks.Count -eq 0) { return }

    Write-Host '  ZeroTier detected.' -ForegroundColor Cyan
    foreach ($net in $networks) {
        $label = if ($net.Name) { "$($net.Name) ($($net.Id))" } else { $net.Id }
        Write-Host "    $label  this machine: $((@($net.Addresses)) -join ', ')" -ForegroundColor DarkGray
    }
    Write-Host '    ZeroTier cannot be auto-discovered: its local client exposes only your own' -ForegroundColor DarkGray
    Write-Host '    address and peer node IDs — not member names or their managed IPs.' -ForegroundColor DarkGray
    Write-Host '    Add a ZeroTier peer by its managed IP, which works like any other address:' -ForegroundColor DarkGray
    Write-Host '      wtw host add <name> --user <u> --address 10.147.20.42 --platform windows' -ForegroundColor DarkGray
    Write-Host ''
}

function Resolve-WtwPeerPlan {
    <#
    .SYNOPSIS
        Work out what `wtw host discover` would do to the current config.
    .DESCRIPTION
        Pure function so the plan can be shown before anything is written, and
        tested without a tailnet.

        Matching against existing hosts is by exact name or alias only — never by
        prefix. A prefix match here would silently merge tailnet addresses into
        the wrong machine's entry, which is far worse than adding a duplicate the
        user can see and remove.

        Tailnet addresses go at the FRONT of the candidate list. `wtw host sync`
        writes the first one that answers, and a tailnet name resolves both on
        the LAN and away from it, so leading with it means the ssh config keeps
        working when you move networks instead of needing a re-sync. The LAN
        names stay behind it as fallback for when Tailscale is down.
    .PARAMETER Peers
        Output of Get-WtwTailscalePeers.
    .PARAMETER Hosts
        Existing hosts from Get-WtwHosts.
    .OUTPUTS
        @{ Name; Action; Platform; Online; AddAddresses; Addresses; Reason }
        Action is one of add | update | ok | skip.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] [object[]] $Peers,
        [AllowNull()] [object[]] $Hosts,
        [AllowNull()] [string[]] $Ignore
    )

    $plan = @()
    foreach ($peer in @($Peers)) {
        if (@($Ignore) -contains $peer.Name) {
            $plan += @{ Name = $peer.Name; Action = 'skip'; Reason = 'excluded'; Online = $peer.Online; Platform = $peer.Platform; AddAddresses = @(); Addresses = @() }
            continue
        }
        if ($peer.IsSelf) {
            $plan += @{ Name = $peer.Name; Action = 'skip'; Reason = 'this machine'; Online = $peer.Online; Platform = $peer.Platform; AddAddresses = @(); Addresses = @() }
            continue
        }
        if (-not $peer.Platform) {
            $plan += @{ Name = $peer.Name; Action = 'skip'; Reason = "$($peer.Os) cannot host a worktree"; Online = $peer.Online; Platform = $null; AddAddresses = @(); Addresses = @() }
            continue
        }

        $existing = @($Hosts) | Where-Object {
            $_.Name -ieq $peer.Name -or (@($_.Aliases) -contains $peer.Name)
        } | Select-Object -First 1

        if (-not $existing) {
            $plan += @{
                Name = $peer.Name; Action = 'add'; Reason = 'new host'
                Online = $peer.Online; Platform = $peer.Platform
                AddAddresses = @($peer.Addresses); Addresses = @($peer.Addresses)
            }
            continue
        }

        $missing = @($peer.Addresses | Where-Object { @($existing.HostNames) -notcontains $_ })
        if ($missing.Count -eq 0) {
            $plan += @{
                Name = $existing.Name; Action = 'ok'; Reason = 'already has its tailnet addresses'
                Online = $peer.Online; Platform = $existing.Platform
                AddAddresses = @(); Addresses = @($existing.HostNames)
            }
            continue
        }

        $plan += @{
            Name = $existing.Name; Action = 'update'; Reason = 'add tailnet addresses'
            Online = $peer.Online; Platform = $existing.Platform
            AddAddresses = $missing
            Addresses = @($missing) + @($existing.HostNames)
        }
    }
    return , @($plan)
}

function Get-WtwZeroTierNetworks {
    <#
    .SYNOPSIS
        ZeroTier networks this machine has joined, with its own managed IPs.
    .DESCRIPTION
        Deliberately limited, because the local ZeroTier client is. `listnetworks`
        returns only *this* node's assigned addresses, and `peers` returns node
        IDs with physical endpoints — no member names and no managed IPs. There is
        therefore no way to enumerate the other members of a ZeroTier network
        locally the way `tailscale status` does; that needs the ZeroTier Central
        API and an account token.

        So this reports your own address per network, which is what you need to
        work out a peer's address by hand, and wtw takes it from there as an
        ordinary `--address` value.
    .OUTPUTS
        @{ Id; Name; Addresses }
    #>
    [CmdletBinding()]
    param([AllowNull()] [object] $Raw)

    if ($null -eq $Raw) {
        if (-not (Get-Command zerotier-cli -ErrorAction SilentlyContinue)) { return , @() }
        $json = & zerotier-cli -j listnetworks 2>$null
        if (-not $json) { return , @() }
        try { $Raw = ($json -join "`n") | ConvertFrom-Json } catch { return , @() }
    }

    $result = @()
    foreach ($net in @($Raw)) {
        $result += @{
            Id        = [string](Get-WtwPropertyValue -Object $net -Name 'id')
            Name      = [string](Get-WtwPropertyValue -Object $net -Name 'name')
            Addresses = @(Get-WtwPropertyValue -Object $net -Name 'assignedAddresses' -DefaultValue @())
        }
    }
    return , @($result)
}
