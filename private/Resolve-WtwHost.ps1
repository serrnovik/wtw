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
        Host name or alias ('arctictroll', 'at').
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
