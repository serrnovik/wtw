$script:WtwSshConfigDir = Join-Path $HOME '.ssh'
$script:WtwSshConfigPath = Join-Path $script:WtwSshConfigDir 'config'
$script:WtwSshManagedRelative = 'config.d/wtw'

function Split-WtwAliasList {
    <#
    .SYNOPSIS
        Normalise an alias argument to a clean string array.
    .DESCRIPTION
        `wtw host add x --alias at,troll` reaches us as @('at','troll') because
        PowerShell's argument mode already splits on commas; the same command
        with the value quoted arrives as the single string 'at,troll'. Accept
        both, and split any element that still contains commas.
    #>
    [CmdletBinding()]
    param([AllowNull()] [string[]] $Value)

    if (-not $Value) { return , @() }
    return , @($Value |
            ForEach-Object { $_ -split ',' } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ })
}

function Get-WtwHosts {
    <#
    .SYNOPSIS
        Remote machines declared in ~/.wtw/config.json.
    .DESCRIPTION
        Hosts live in the user config, not in a repo file. A repo-level map would
        duplicate what the remote's own wtw registry already knows and would go
        stale every time an agent creates or removes a worktree over there —
        which, in an agent-driven setup, is constantly.
    .OUTPUTS
        Array of @{ Name; Aliases; User; HostName; Port; IdentityFile;
                    IdentitiesOnly; Platform; Wtw }.
    #>
    [CmdletBinding()]
    param([AllowNull()] [object] $Config)

    if ($null -eq $Config) { $Config = Get-WtwConfig }
    $hosts = Get-WtwPropertyValue -Object $Config -Name 'hosts'
    if (-not $hosts) { return , @() }

    $result = @()
    foreach ($name in (Get-WtwPropertyNames -Object $hosts)) {
        $entry = Get-WtwPropertyValue -Object $hosts -Name $name

        # `hostNames` is an ordered candidate list — an mDNS name first, a
        # last-known IP as backup — because a laptop on DHCP (or moving between
        # wifi and a USB adapter) changes address constantly while its .local
        # name does not. `hostName` (singular) is the pre-0.2 single-value form.
        $candidates = @(Get-WtwPropertyValue -Object $entry -Name 'hostNames' -DefaultValue @())
        if ($candidates.Count -eq 0) {
            $legacy = Get-WtwPropertyValue -Object $entry -Name 'hostName'
            if ($legacy) { $candidates = @($legacy) }
        }

        $result += @{
            Name           = $name
            Aliases        = @(Get-WtwPropertyValue -Object $entry -Name 'aliases' -DefaultValue @())
            User           = Get-WtwPropertyValue -Object $entry -Name 'user'
            HostNames      = $candidates
            HostName       = ($candidates | Select-Object -First 1)
            Port           = Get-WtwPropertyValue -Object $entry -Name 'port'
            IdentityFile   = Get-WtwPropertyValue -Object $entry -Name 'identityFile'
            IdentitiesOnly = Get-WtwPropertyValue -Object $entry -Name 'identitiesOnly' -DefaultValue $false
            # Drives both the remote URI path shape (drive letters) and whether
            # remote.SSH.remotePlatform needs pinning in the editor's settings.
            Platform       = (Get-WtwPropertyValue -Object $entry -Name 'platform' -DefaultValue 'linux')
            Wtw            = (Get-WtwPropertyValue -Object $entry -Name 'wtw' -DefaultValue 'wtw')
            # Explicit pwsh path, for installs the standard probe list misses.
            Pwsh           = (Get-WtwPropertyValue -Object $entry -Name 'pwsh')
            # Preferred transport: tailscale | zerotier | mdns | lan | any.
            Via            = (Get-WtwPropertyValue -Object $entry -Name 'via')
            # Identity in terminal titles: a per-machine emoji and a short label,
            # so a remote tab is recognisable as "that machine" at a glance.
            Emoji          = (Get-WtwPropertyValue -Object $entry -Name 'emoji')
            Label          = (Get-WtwPropertyValue -Object $entry -Name 'label')
            # What goes between the machine label and the worktree title. '.' by
            # default; a space or '' reads better when the worktree name starts
            # with its own emoji.
            Separator      = (Get-WtwPropertyValue -Object $entry -Name 'separator' -DefaultValue '.')
        }
    }
    # Comma operator: without it a single configured host unrolls to a bare
    # hashtable, and `(Get-WtwHosts)[0]` becomes a key lookup returning $null.
    return , @($result)
}

function Resolve-WtwHost {
    <#
    .SYNOPSIS
        Resolve a host name or alias to its configured entry.
    .DESCRIPTION
        Exact name, then exact alias, then unique prefix across both. Prefix
        resolution is deliberately strict: an ambiguous prefix returns $null
        rather than guessing, because guessing wrong here opens an editor
        against the wrong machine's filesystem.
    .PARAMETER Name
        Host name or alias ('workstation', 'at').
    .PARAMETER Hosts
        Pre-read host list. Defaults to the configured hosts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [AllowNull()] [object[]] $Hosts
    )

    if ($null -eq $Hosts) { $Hosts = Get-WtwHosts }
    if ($Hosts.Count -eq 0) { return $null }

    $exact = $Hosts | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
    if ($exact) { return $exact }

    $byAlias = $Hosts | Where-Object { @($_.Aliases) -contains $Name } | Select-Object -First 1
    if ($byAlias) { return $byAlias }

    $prefixed = @($Hosts | Where-Object {
            $_.Name.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase) -or
            (@($_.Aliases) | Where-Object { $_.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase) })
        })
    if ($prefixed.Count -eq 1) { return $prefixed[0] }

    return $null
}

function Get-WtwLocalMachineName {
    <#
    .SYNOPSIS
        This machine's own names, for spotting a --on that points at itself.
    .DESCRIPTION
        Returns the OS hostname, its first DNS label, and the tailnet name when
        Tailscale is present — the same forms a host entry is likely to use.
    #>
    [CmdletBinding()]
    param()

    $names = @()
    try { $names += [System.Net.Dns]::GetHostName() } catch { Write-Verbose "hostname: $_" }
    if ($env:COMPUTERNAME) { $names += $env:COMPUTERNAME }

    try {
        # Assign before piping: the function returns `,@(...)`, so piping it
        # directly hands Where-Object the whole array as ONE item, `$_.IsSelf`
        # evaluates to an array of booleans, and every peer "matches".
        $peers = Get-WtwTailscalePeers
        $self = $peers | Where-Object { $_.IsSelf } | Select-Object -First 1
        if ($self) {
            $names += $self.Name
            if ($self.DnsName) { $names += $self.DnsName }
        }
    } catch { Write-Verbose "tailscale self: $_" }

    # First label too: 'box.tailnet.ts.net' should also answer to 'box'.
    $expanded = @($names | Where-Object { $_ } | ForEach-Object { $_; ($_ -split '\.')[0] })
    return , @($expanded | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
}

function Test-WtwIsLocalMachine {
    <#
    .SYNOPSIS
        Does this name refer to the machine we are already on?
    .DESCRIPTION
        `--on` names the OTHER machine. Pointing it at this one is a common
        direction mix-up when the same aliases exist on both sides, and without
        this check it surfaces as a bare "unknown host", which does not hint at
        the actual mistake.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)

    return ((Get-WtwLocalMachineName) -contains $Name.ToLowerInvariant())
}

function Get-WtwHostTitlePrefix {
    <#
    .SYNOPSIS
        The "which machine am I on" prefix for a terminal title.
    .DESCRIPTION
        Produces `🧊AT.` for a host configured with emoji 🧊 and label AT, so a
        remote tab reads `🧊AT.🟢 PF037 …` — machine first, then the worktree's
        own title. With a dozen tabs open, the machine is the thing you need to
        recognise before anything else.

        The separator is configurable because the worktree half usually starts
        with its own emoji, and a '.' immediately before an emoji reads cramped.
        A space, or nothing at all, often looks better.

        The label defaults to the shortest alias upper-cased, then to the first
        two letters of the host name, so this is useful without configuring
        anything. An emoji is only shown when set; there is no default, because
        an arbitrary auto-assigned emoji per machine would be noise rather than
        identity.
    .PARAMETER HostEntry
        Host entry from Resolve-WtwHost.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $HostEntry)

    $emoji = Get-WtwPropertyValue -Object $HostEntry -Name 'Emoji'
    $label = Get-WtwPropertyValue -Object $HostEntry -Name 'Label'

    if (-not $label) {
        $aliases = @(Get-WtwPropertyValue -Object $HostEntry -Name 'Aliases' -DefaultValue @()) |
            Where-Object { $_ }
        $label = if ($aliases.Count -gt 0) {
            (@($aliases | Sort-Object { $_.Length }) | Select-Object -First 1).ToUpperInvariant()
        } else {
            $name = [string](Get-WtwPropertyValue -Object $HostEntry -Name 'Name')
            if ($name.Length -ge 2) { $name.Substring(0, 2).ToUpperInvariant() } else { $name.ToUpperInvariant() }
        }
    }

    $separator = Get-WtwPropertyValue -Object $HostEntry -Name 'Separator' -DefaultValue '.'
    return "$emoji$label$separator"
}

function Resolve-WtwHostVia {
    <#
    .SYNOPSIS
        Retarget a host at one transport, for a single command.
    .DESCRIPTION
        `wtw --on at list --via tailscale` is a one-off override — it must not
        touch the stored config the way `wtw host add --via` does.

        The trick is to return a host entry whose Name IS the chosen address.
        Everything downstream already keys off Name: ssh connects to it, and the
        editor authority becomes `ssh-remote+<address>`. Both work because
        Sync-WtwSshConfig also emits every candidate address as a Host pattern
        carrying the same User and IdentityFile.
    .PARAMETER HostEntry
        Entry from Resolve-WtwHost.
    .PARAMETER Via
        tailscale | zerotier | mdns | lan | any. Empty or 'any' returns the entry
        unchanged, so callers can pass through unconditionally.
    .OUTPUTS
        The retargeted entry, or $null when the host has no address of that kind.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [AllowNull()] [string] $Via
    )

    if (-not $Via -or $Via -eq 'any') { return $HostEntry }

    $prefixes = Get-WtwZeroTierPrefixes
    $match = @(@($HostEntry.HostNames) |
            Where-Object { (Get-WtwAddressKind -Address $_ -ZeroTierPrefixes $prefixes) -eq $Via }) |
        Select-Object -First 1
    if (-not $match) { return $null }

    $clone = @{}
    foreach ($key in $HostEntry.Keys) { $clone[$key] = $HostEntry[$key] }
    $clone['Name'] = $match
    $clone['HostNames'] = @($match)
    $clone['ViaOverride'] = $Via
    return $clone
}

function Get-WtwHostNames {
    <#
    .SYNOPSIS
        Every name and alias that can address a configured host.
    .DESCRIPTION
        Used by the `--on`-less shorthand (`wtw at cursor auth`) and by tab
        completion, both of which need the flat token list rather than entries.
    #>
    [CmdletBinding()]
    param([AllowNull()] [object[]] $Hosts)

    if ($null -eq $Hosts) { $Hosts = Get-WtwHosts }
    $names = @()
    foreach ($h in $Hosts) {
        $names += $h.Name
        $names += @($h.Aliases)
    }
    return , @($names | Where-Object { $_ } | Select-Object -Unique)
}
