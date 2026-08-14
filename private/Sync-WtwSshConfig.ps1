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
    if ($candidates.Count -eq 0) { return @{ Address = $null; Reachable = $false } }

    $port = if ($HostEntry.Port) { [int]$HostEntry.Port } else { 22 }
    foreach ($candidate in $candidates) {
        if (Test-WtwAddressReachable -Address $candidate -Port $port) {
            return @{ Address = $candidate; Reachable = $true }
        }
    }
    return @{ Address = $candidates[0]; Reachable = $false }
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
