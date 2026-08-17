function Get-WtwAddressKind {
    <#
    .SYNOPSIS
        Classify a candidate address by the transport it implies.
    .DESCRIPTION
        The candidate list mixes networks — a tailnet name, a mDNS name, a LAN
        IP — and which one is in use decides whether the connection survives you
        leaving the house. Labelling them makes `wtw host list/show` legible and
        gives `--via` something to select on.

        Tailscale is identified by its MagicDNS suffix or by the 100.64.0.0/10
        CGNAT range it assigns. ZeroTier cannot be identified by shape (it hands
        out ordinary RFC1918 addresses), so it is matched against the subnets
        this machine has actually joined — which is the one thing the local
        ZeroTier client does tell us.
    .PARAMETER Address
        Hostname or IP.
    .PARAMETER ZeroTierPrefixes
        Assigned subnets from Get-WtwZeroTierNetworks, e.g. @('10.147.20.').
    .OUTPUTS
        tailscale | zerotier | mdns | lan | other
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Address,
        [AllowNull()] [string[]] $ZeroTierPrefixes
    )

    if ($Address -match '\.ts\.net$') { return 'tailscale' }
    # 100.64.0.0/10 → second octet 64-127.
    if ($Address -match '^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.') { return 'tailscale' }

    foreach ($prefix in @($ZeroTierPrefixes)) {
        if ($prefix -and $Address.StartsWith($prefix)) { return 'zerotier' }
    }

    if ($Address -match '\.local$') { return 'mdns' }
    if ($Address -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)') { return 'lan' }
    return 'other'
}

function Get-WtwZeroTierPrefixes {
    <#
    .SYNOPSIS
        Network prefixes for the ZeroTier networks this machine has joined.
    .DESCRIPTION
        Turns "10.147.20.128/24" into "10.147.20." so peer addresses on the same
        network can be recognised. Only /24 and larger-octet-aligned masks are
        handled, which covers ZeroTier's defaults; anything else falls back to
        being classified as a plain LAN address, which is cosmetic only.
    #>
    [CmdletBinding()]
    param([AllowNull()] [object[]] $Networks)

    if ($null -eq $Networks) { $Networks = Get-WtwZeroTierNetworks }

    $prefixes = @()
    foreach ($net in @($Networks)) {
        foreach ($assigned in @($net.Addresses)) {
            $ip = ($assigned -split '/')[0]
            $octets = $ip -split '\.'
            if ($octets.Count -eq 4) { $prefixes += "$($octets[0]).$($octets[1]).$($octets[2])." }
        }
    }
    return , @($prefixes | Select-Object -Unique)
}

function Test-WtwAddressReachable {
    <#
    .SYNOPSIS
        Can we open a TCP connection to this address:port?
    .DESCRIPTION
        A plain TcpClient probe with an explicit timeout. `Test-Connection` uses
        ICMP, which Windows blocks by default — a box that happily accepts ssh
        would look unreachable.
    .PARAMETER Address
        Hostname or IP.
    .PARAMETER Port
        TCP port (default 22).
    .PARAMETER TimeoutMs
        Per-candidate budget. Kept short: this runs once per candidate on sync,
        and an unreachable name should not stall the command.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Address,
        [int] $Port = 22,
        [int] $TimeoutMs = 1200
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $async = $client.BeginConnect($Address, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Resolve-WtwHostAddress {
    <#
    .SYNOPSIS
        Pick the first candidate address that actually answers on the ssh port.
    .DESCRIPTION
        Falls back to the first candidate when none answers, so a sync run while
        the other machine is asleep still writes a usable config rather than
        emptying it.
    .OUTPUTS
        @{ Address; Reachable }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $HostEntry)

    # Re-wrap the filter: with a single candidate Where-Object yields a bare
    # string, and `.Count` on a string throws under strict mode — which is every
    # host configured with one address.
    $candidates = @(@($HostEntry.HostNames) | Where-Object { $_ })
    if ($candidates.Count -eq 0) { return @{ Address = $null; Reachable = $false; Kind = $null; Preferred = $true } }

    $port = if ($HostEntry.Port) { [int]$HostEntry.Port } else { 22 }
    $ztPrefixes = Get-WtwZeroTierPrefixes
    $via = Get-WtwPropertyValue -Object $HostEntry -Name 'Via'

    # A `via` preference reorders rather than filters. Pinning a transport should
    # not make the host unreachable when that transport is down — it should just
    # be tried first, and the caller is told when the fallback kicked in.
    # @() around the whole if-expression: assigning from `if` sends the value
    # through the pipeline, which unrolls a one-element array to a bare string —
    # and then $ordered[0] below yields its first CHARACTER, so a single-address
    # host that is momentarily unreachable got "HostName 1" written into ssh config.
    $ordered = @(
        if ($via -and $via -ne 'any') {
            @($candidates | Where-Object { (Get-WtwAddressKind -Address $_ -ZeroTierPrefixes $ztPrefixes) -eq $via }) +
            @($candidates | Where-Object { (Get-WtwAddressKind -Address $_ -ZeroTierPrefixes $ztPrefixes) -ne $via })
        } else {
            $candidates
        }
    )

    foreach ($candidate in $ordered) {
        if (Test-WtwAddressReachable -Address $candidate -Port $port) {
            $kind = Get-WtwAddressKind -Address $candidate -ZeroTierPrefixes $ztPrefixes
            return @{
                Address   = $candidate
                Reachable = $true
                Kind      = $kind
                Preferred = (-not $via -or $via -eq 'any' -or $kind -eq $via)
            }
        }
    }
    return @{
        Address   = $ordered[0]
        Reachable = $false
        Kind      = (Get-WtwAddressKind -Address $ordered[0] -ZeroTierPrefixes $ztPrefixes)
        Preferred = $true
    }
}

function New-WtwSshConfigBlock {
    <#
    .SYNOPSIS
        Render configured wtw hosts as an OpenSSH config fragment.
    .DESCRIPTION
        Each host becomes one `Host` line carrying its name *and* its aliases, so
        `ssh at` and `ssh-remote+at` both work without a second block.

        This fragment exists because the Remote-SSH extension resolves
        `ssh-remote+<host>` through the ssh client, not through wtw. Whatever
        wtw knows about a host is invisible to the editor unless it lands in
        ssh's own config.
    .PARAMETER Hosts
        Host entries from Get-WtwHosts.
    #>
    [CmdletBinding()]
    param([AllowNull()] [object[]] $Hosts)

    if ($null -eq $Hosts) { $Hosts = Get-WtwHosts }

    $lines = @(
        '# Managed by wtw — do not edit by hand.'
        '# Regenerate with: wtw host sync'
        ''
    )
    foreach ($h in ($Hosts | Sort-Object { $_.Name })) {
        $patterns = @($h.Name) + @($h.Aliases | Where-Object { $_ -and $_ -ne $h.Name })
        $lines += "Host $((@($patterns) | Select-Object -Unique) -join ' ')"

        # ssh config takes exactly one HostName, so a multi-candidate host is
        # resolved here — first one answering on the ssh port wins.
        $resolved = Resolve-WtwHostAddress -HostEntry $h
        if (@($h.HostNames).Count -gt 1) {
            $note = if ($resolved.Reachable) { 'reachable' } else { 'no candidate answered; using the first' }
            $lines += "    # candidates: $((@($h.HostNames)) -join ', ')  ($note)"
        }
        if ($resolved.Address)  { $lines += "    HostName $($resolved.Address)" }
        if ($h.User)         { $lines += "    User $($h.User)" }
        if ($h.Port)         { $lines += "    Port $($h.Port)" }
        if ($h.IdentityFile) { $lines += "    IdentityFile $($h.IdentityFile)" }
        if ($h.IdentitiesOnly) { $lines += '    IdentitiesOnly yes' }
        $lines += ''

        # Second block: every candidate address as a Host pattern, with the same
        # credentials but deliberately NO HostName — so ssh uses the pattern
        # itself as the address.
        #
        # This is what makes a per-invocation `--via` possible. Overriding the
        # transport for one command means targeting a specific address rather
        # than the host name, and the editor's `ssh-remote+<authority>` resolves
        # through the ssh client too — so the address has to carry User and
        # IdentityFile on its own, not just inside the named block.
        $alternates = @($h.HostNames) | Where-Object { $_ -and $_ -ne $resolved.Address }
        if (@($alternates).Count -gt 0 -or $h.HostNames.Count -gt 0) {
            $lines += "Host $((@($h.HostNames) | Select-Object -Unique) -join ' ')"
            if ($h.User)         { $lines += "    User $($h.User)" }
            if ($h.Port)         { $lines += "    Port $($h.Port)" }
            if ($h.IdentityFile) { $lines += "    IdentityFile $($h.IdentityFile)" }
            if ($h.IdentitiesOnly) { $lines += '    IdentitiesOnly yes' }
            $lines += ''
        }
    }
    return ($lines -join "`n")
}

function Sync-WtwSshConfig {
    <#
    .SYNOPSIS
        Write ~/.ssh/config.d/wtw and make sure ~/.ssh/config includes it.
    .DESCRIPTION
        The Include line is *prepended*, never appended. OpenSSH applies the
        first obtained value for each keyword, so an Include placed after an
        existing `Host` block would be parsed inside that block's scope and the
        wtw hosts would only apply to it. Prepending keeps the fragment global.

        wtw only ever owns its own fragment file; the user's ~/.ssh/config is
        touched exactly once, to add the Include.
    .PARAMETER Hosts
        Host entries to write. Defaults to the configured hosts.
    .PARAMETER Quiet
        Suppress progress output.
    .OUTPUTS
        Path to the managed fragment.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] [object[]] $Hosts,
        [switch] $Quiet
    )

    if ($null -eq $Hosts) { $Hosts = Get-WtwHosts }

    $managedPath = Join-Path $script:WtwSshConfigDir 'config.d' 'wtw'
    $managedDir = Split-Path $managedPath -Parent
    if (-not (Test-Path $managedDir)) {
        New-Item -ItemType Directory -Path $managedDir -Force | Out-Null
    }

    Set-Content -Path $managedPath -Value (New-WtwSshConfigBlock -Hosts $Hosts) -Encoding utf8
    if (-not $IsWindows) {
        # ssh refuses to read a config file that is group/world readable.
        & chmod 600 $managedPath 2>$null
    }

    $includeLine = "Include $script:WtwSshManagedRelative"
    if (-not (Test-Path $script:WtwSshConfigPath)) {
        Set-Content -Path $script:WtwSshConfigPath -Value "$includeLine`n" -Encoding utf8
        if (-not $IsWindows) { & chmod 600 $script:WtwSshConfigPath 2>$null }
        if (-not $Quiet) { Write-Host "  Created $script:WtwSshConfigPath with the wtw include." -ForegroundColor Green }
        return $managedPath
    }

    $existing = Get-Content -Path $script:WtwSshConfigPath -Raw
    if ($existing -match [regex]::Escape($script:WtwSshManagedRelative)) {
        if (-not $Quiet) { Write-Host "  Wrote $managedPath (already included)." -ForegroundColor Green }
        return $managedPath
    }

    Set-Content -Path $script:WtwSshConfigPath -Value "$includeLine`n`n$existing" -Encoding utf8
    if (-not $Quiet) {
        Write-Host "  Wrote $managedPath" -ForegroundColor Green
        Write-Host "  Prepended '$includeLine' to $script:WtwSshConfigPath" -ForegroundColor Green
    }
    return $managedPath
}

function Get-WtwSshHostConflicts {
    <#
    .SYNOPSIS
        Other `Host` blocks in the user's ssh config that match a wtw host.
    .DESCRIPTION
        wtw's fragment is Include'd at the very top, and OpenSSH takes the FIRST
        obtained value for each keyword — so a hand-written or chezmoi-managed
        `Host workstation` further down still parses, but its HostName, User and
        IdentityFile are silently overridden by wtw's.

        That is usually harmless (same machine, same key) but it is invisible,
        and it means anything else relying on that name — an editor's remote
        project, a chezmoi-managed entry — quietly follows whichever address wtw
        last synced. Surfacing it lets the user decide.

        Only the *other* files are scanned; wtw's own fragment is the baseline,
        not a conflict.
    .PARAMETER Name
        Host name to look for.
    .PARAMETER Aliases
        Additional patterns that address the same host.
    .OUTPUTS
        @{ File; Line; Text }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [AllowNull()] [string[]] $Aliases
    )

    $patterns = @($Name) + @($Aliases) | Where-Object { $_ } | Select-Object -Unique
    $managed = Join-Path $script:WtwSshConfigDir 'config.d' 'wtw'

    $files = @()
    if (Test-Path $script:WtwSshConfigPath) { $files += $script:WtwSshConfigPath }
    $configD = Join-Path $script:WtwSshConfigDir 'config.d'
    if (Test-Path $configD) {
        $files += @(Get-ChildItem -Path $configD -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    }

    $conflicts = @()
    foreach ($file in ($files | Select-Object -Unique)) {
        if ([System.IO.Path]::GetFullPath($file) -eq [System.IO.Path]::GetFullPath($managed)) { continue }

        $lineNumber = 0
        foreach ($line in (Get-Content -Path $file -ErrorAction SilentlyContinue)) {
            $lineNumber++
            if ($line -notmatch '^\s*Host\s+(.+?)\s*$') { continue }
            # Split the pattern list and compare whole tokens, so `Host workstation2`
            # is not reported as a conflict with `workstation`.
            $tokens = @($Matches[1] -split '\s+')
            if (@($tokens | Where-Object { $patterns -contains $_ }).Count -gt 0) {
                $conflicts += @{ File = $file; Line = $lineNumber; Text = $line.Trim() }
            }
        }
    }
    return , @($conflicts)
}

function Get-WtwSshEffectiveHostName {
    <#
    .SYNOPSIS
        The HostName the ssh client will actually use for a name.
    .DESCRIPTION
        `ssh -G` prints the effective config after all Host blocks and Includes
        are merged, so this is the ground truth — not what wtw last intended to
        write. Returns $null when ssh only echoes the name back, which is how an
        unconfigured host presents.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { return $null }
    $output = & ssh -G $Name 2>$null
    if (-not $output) { return $null }
    $line = $output | Where-Object { $_ -match '^hostname\s+(.+)$' } | Select-Object -First 1
    if (-not $line) { return $null }
    $resolved = ($line -replace '^hostname\s+', '').Trim()
    if (-not $resolved -or $resolved -eq $Name) { return $null }
    return $resolved
}

function Test-WtwSshHostKnown {
    <#
    .SYNOPSIS
        Does the ssh client already resolve this host name?
    .DESCRIPTION
        `ssh -G <host>` prints the effective config. When the host is unknown,
        `hostname` echoes the literal name back — which is how we tell a real
        config entry from ssh's default passthrough. Used to warn *before*
        handing a `ssh-remote+<host>` authority to an editor that would
        otherwise fail with an opaque connection error.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { return $false }
    $output = & ssh -G $Name 2>$null
    if (-not $output) { return $false }
    $hostLine = $output | Where-Object { $_ -match '^hostname\s+(.+)$' } | Select-Object -First 1
    if (-not $hostLine) { return $false }
    $resolved = ($hostLine -replace '^hostname\s+', '').Trim()
    return ($resolved -and $resolved -ne $Name)
}
