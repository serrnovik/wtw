function Invoke-WtwHost {
    <#
    .SYNOPSIS
        Manage the remote machines wtw can open worktrees on.
    .DESCRIPTION
        Hosts are stored in ~/.wtw/config.json under `hosts`, and mirrored into
        ~/.ssh/config.d/wtw so the editor's Remote-SSH extension — which resolves
        hosts through the ssh client, not through wtw — can see them too.

        Subcommands:
          list                     Show configured hosts and their ssh status
          add <name> [options]     Add or update a host, then sync ssh config
          remove <name>            Drop a host, then sync ssh config
          sync                     Re-probe addresses, rewrite ~/.ssh/config.d/wtw
          trust <name>             Show host-key fingerprints, then add to known_hosts
          test <name>              Probe addresses, ssh config, and the remote wtw
    .PARAMETER Action
        Subcommand (default: list).
    .PARAMETER Name
        Host name for add / remove / test.
    .PARAMETER Alias
        Short aliases, e.g. "at,troll". Typed as an array because PowerShell's
        argument mode already turns a bare `at,troll` into two arguments, while a
        quoted 'at,troll' arrives as one string — both forms are accepted.
    .PARAMETER User
        SSH user.
    .PARAMETER Address
        Ordered candidate addresses for ssh. Prefer an mDNS name
        (`snowpomme.local`) first and a last-known IP as backup: on DHCP — or
        when a machine moves between wifi and a USB adapter — the address changes
        but the .local name does not. `wtw host sync` writes whichever candidate
        answers on the ssh port.
    .PARAMETER Identity
        IdentityFile path.
    .PARAMETER Port
        SSH port.
    .PARAMETER Platform
        Remote OS: windows | linux | macos. Drives remote path translation.
    .PARAMETER Wtw
        Command used to invoke wtw on the remote (default: wtw).
    .EXAMPLE
        wtw host add arctictroll --alias at --user sno --address 192.168.3.7 --platform windows --identity ~/.ssh/id_ed25519_arctictroll
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)] [string] $Action = 'list',
        [Parameter(Position = 1)] [string] $Name,
        [string[]] $Alias,
        [string] $User,
        [string[]] $Address,
        [string] $Identity,
        [string] $Port,
        [ValidateSet('windows', 'linux', 'macos')] [string] $Platform = 'linux',
        [string] $Wtw
    )

    switch ($Action.ToLowerInvariant()) {
        'list' {
            $hosts = Get-WtwHosts
            if ($hosts.Count -eq 0) {
                Write-Host ''
                Write-Host '  No remote hosts configured.' -ForegroundColor Yellow
                Write-Host '  Add one:  wtw host add arctictroll --alias at --user sno --address 192.168.3.7 --platform windows' -ForegroundColor DarkGray
                Write-Host ''
                return
            }
            Write-Host ''
            foreach ($h in ($hosts | Sort-Object { $_.Name })) {
                $aliases = if (@($h.Aliases).Count -gt 0) { " (" + (@($h.Aliases) -join ', ') + ")" } else { '' }
                $known = if (Test-WtwSshHostKnown -Name $h.Name) { 'ssh ok' } else { 'not in ssh config — run: wtw host sync' }
                $knownColor = if ($known -eq 'ssh ok') { 'DarkGray' } else { 'Yellow' }
                Write-Host "  $($h.Name)$aliases" -ForegroundColor Cyan -NoNewline
                Write-Host "  $($h.User)@$($h.HostName)  [$($h.Platform)]" -ForegroundColor White -NoNewline
                Write-Host "  $known" -ForegroundColor $knownColor
                if (@($h.HostNames).Count -gt 1) {
                    Write-Host "      candidates: $((@($h.HostNames)) -join ', ')" -ForegroundColor DarkGray
                }
            }
            Write-Host ''
        }

        'add' {
            if (-not $Name) { Write-Error 'Usage: wtw host add <name> [--alias a,b] [--user u] [--address ip] [--identity path] [--port n] [--platform windows|linux|macos]'; return }

            $config = Get-WtwConfig
            if (-not $config) { $config = New-WtwDefaultConfig }

            $hosts = Get-WtwPropertyValue -Object $config -Name 'hosts'
            if (-not $hosts) { $hosts = [PSCustomObject]@{} }

            $existing = Get-WtwPropertyValue -Object $hosts -Name $Name
            $entry = if ($existing) { $existing } else { [PSCustomObject]@{} }

            # Only overwrite what was actually passed, so `wtw host add x --platform windows`
            # is a targeted edit rather than a silent reset of the other fields.
            if ($Alias)    { $entry | Add-Member -NotePropertyName 'aliases' -NotePropertyValue (Split-WtwAliasList -Value $Alias) -Force }
            if ($User)     { $entry | Add-Member -NotePropertyName 'user' -NotePropertyValue $User -Force }
            if ($Address) {
                # Stored as an ordered candidate list. Put the mDNS name first
                # and a last-known IP second: on DHCP the address moves, the
                # .local name does not.
                $entry | Add-Member -NotePropertyName 'hostNames' -NotePropertyValue (Split-WtwAliasList -Value $Address) -Force
                # Drop the pre-0.2 single-value key so the two cannot disagree.
                if ((Get-WtwPropertyNames -Object $entry) -contains 'hostName') {
                    $entry.PSObject.Properties.Remove('hostName')
                }
            }
            if ($Identity) { $entry | Add-Member -NotePropertyName 'identityFile' -NotePropertyValue $Identity -Force; $entry | Add-Member -NotePropertyName 'identitiesOnly' -NotePropertyValue $true -Force }
            if ($Port)     { $entry | Add-Member -NotePropertyName 'port' -NotePropertyValue $Port -Force }
            if ($Wtw)      { $entry | Add-Member -NotePropertyName 'wtw' -NotePropertyValue $Wtw -Force }
            if ($PSBoundParameters.ContainsKey('Platform') -or -not (Get-WtwPropertyValue -Object $entry -Name 'platform')) {
                $entry | Add-Member -NotePropertyName 'platform' -NotePropertyValue $Platform -Force
            }

            $hosts | Add-Member -NotePropertyName $Name -NotePropertyValue $entry -Force
            $config | Add-Member -NotePropertyName 'hosts' -NotePropertyValue $hosts -Force
            Save-WtwConfig $config

            Write-Host "  Saved host '$Name'." -ForegroundColor Green
            Sync-WtwSshConfig | Out-Null
        }

        'remove' {
            if (-not $Name) { Write-Error 'Usage: wtw host remove <name>'; return }
            $config = Get-WtwConfig
            $hosts = Get-WtwPropertyValue -Object $config -Name 'hosts'
            if (-not $hosts -or -not ((Get-WtwPropertyNames -Object $hosts) -contains $Name)) {
                Write-Error "Host '$Name' is not configured."
                return
            }
            $hosts.PSObject.Properties.Remove($Name)
            Save-WtwConfig $config
            Write-Host "  Removed host '$Name'." -ForegroundColor Green
            Sync-WtwSshConfig | Out-Null
        }

        'sync' {
            $hosts = Get-WtwHosts
            if ($hosts.Count -eq 0) {
                Write-Host '  No hosts configured — nothing to sync.' -ForegroundColor Yellow
                return
            }
            Sync-WtwSshConfig | Out-Null
        }

        'trust' {
            if (-not $Name) { Write-Error 'Usage: wtw host trust <name>'; return }
            $entry = Resolve-WtwHost -Name $Name
            if (-not $entry) { Write-Error "Host '$Name' is not configured. See: wtw host list"; return }
            if (-not (Get-Command ssh-keyscan -ErrorAction SilentlyContinue)) {
                Write-Error "ssh-keyscan is not on PATH. Accept the key manually instead: ssh $($entry.Name)"
                return
            }

            # Every candidate address needs its own known_hosts entry — ssh
            # trusts a key per host pattern, so reaching the same machine by
            # .local after trusting its IP is a fresh, unverified connection.
            $targets = @($entry.Name) + @($entry.HostNames) | Where-Object { $_ } | Select-Object -Unique
            $port = if ($entry.Port) { [int]$entry.Port } else { 22 }

            $keys = @()
            foreach ($target in $targets) {
                $scanned = @(& ssh-keyscan -p $port -T 5 $target 2>$null | Where-Object { $_ -and $_ -notmatch '^#' })
                if ($scanned.Count -gt 0) { $keys += $scanned }
            }
            if ($keys.Count -eq 0) {
                Write-Error "ssh-keyscan got no keys for $($targets -join ', '). Is the machine up?"
                return
            }

            # Key material already in known_hosts, keyed by the base64 blob. A
            # scanned key that matches one you already trust under a different
            # name is the same machine answering to a new address — which turns
            # this from blind trust-on-first-use into a comparison you can check.
            $knownHostsPath = Join-Path $script:WtwSshConfigDir 'known_hosts'
            $trustedMaterial = @{}
            if (Test-Path $knownHostsPath) {
                foreach ($line in (Get-Content $knownHostsPath)) {
                    $parts = $line -split '\s+'
                    if ($parts.Count -ge 3 -and $parts[2]) { $trustedMaterial[$parts[2]] = $parts[0] }
                }
            }

            Write-Host ''
            Write-Host '  Host keys offered:' -ForegroundColor Cyan
            $anyAlreadyTrusted = $false
            foreach ($key in ($keys | Select-Object -Unique)) {
                $fields = $key -split '\s+'
                $fingerprint = '(fingerprint unavailable)'
                try {
                    $tmp = [System.IO.Path]::GetTempFileName()
                    Set-Content -Path $tmp -Value $key -Encoding ascii
                    $fingerprint = ((& ssh-keygen -l -f $tmp 2>$null) | Select-Object -First 1)
                    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
                } catch { }

                $material = if ($fields.Count -ge 3) { $fields[2] } else { $null }
                $match = if ($material -and $trustedMaterial.ContainsKey($material)) { $trustedMaterial[$material] } else { $null }

                Write-Host "    $($fields[0])  $fingerprint" -ForegroundColor White -NoNewline
                if ($match) {
                    $anyAlreadyTrusted = $true
                    Write-Host "  ← same key you already trust for $match" -ForegroundColor Green
                } else {
                    Write-Host ''
                }
            }

            Write-Host ''
            if ($anyAlreadyTrusted) {
                Write-Host '  Keys marked above already match a host you trust, so those are the same' -ForegroundColor Green
                Write-Host '  machine reachable under another name.' -ForegroundColor Green
            } else {
                Write-Host '  None of these match a host you already trust. Verify against the machine:' -ForegroundColor Yellow
                Write-Host '    on that host, run:  ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub' -ForegroundColor DarkGray
                Write-Host '    (Windows OpenSSH:   ssh-keygen -lf $env:ProgramData\ssh\ssh_host_ed25519_key.pub)' -ForegroundColor DarkGray
            }
            Write-Host ''

            $answer = Read-Host "  Add these to ~/.ssh/known_hosts? [y/N]"
            if ($answer -notin @('y', 'Y', 'yes')) {
                Write-Host '  Not added.' -ForegroundColor DarkGray
                return
            }

            $knownHosts = Join-Path $script:WtwSshConfigDir 'known_hosts'
            if (-not (Test-Path $script:WtwSshConfigDir)) {
                New-Item -ItemType Directory -Path $script:WtwSshConfigDir -Force | Out-Null
            }
            $existing = if (Test-Path $knownHosts) { @(Get-Content $knownHosts) } else { @() }
            $added = 0
            foreach ($key in ($keys | Select-Object -Unique)) {
                if ($existing -notcontains $key) {
                    Add-Content -Path $knownHosts -Value $key -Encoding ascii
                    $added++
                }
            }
            Write-Host "  Added $added key(s) to $knownHosts." -ForegroundColor Green
        }

        'test' {
            if (-not $Name) { Write-Error 'Usage: wtw host test <name>'; return }
            $entry = Resolve-WtwHost -Name $Name
            if (-not $entry) { Write-Error "Host '$Name' is not configured. See: wtw host list"; return }

            Write-Host ''
            Write-Host "  addresses     " -NoNewline
            $resolved = Resolve-WtwHostAddress -HostEntry $entry
            if ($resolved.Reachable) {
                Write-Host "$($resolved.Address) answers on ssh" -ForegroundColor Green
            } else {
                Write-Host "none of [$((@($entry.HostNames)) -join ', ')] answered" -ForegroundColor Red
            }

            Write-Host "  ssh config    " -NoNewline
            if (Test-WtwSshHostKnown -Name $entry.Name) {
                $configured = (& ssh -G $entry.Name 2>$null |
                        Where-Object { $_ -match '^hostname\s+(.+)$' } |
                        Select-Object -First 1) -replace '^hostname\s+', ''
                if ($resolved.Reachable -and $configured.Trim() -ne $resolved.Address) {
                    # The stored address went stale — normal on DHCP.
                    Write-Host "resolves to $($configured.Trim()), but $($resolved.Address) is the live one — run: wtw host sync" -ForegroundColor Yellow
                } else {
                    Write-Host 'resolves' -ForegroundColor Green
                }
            } else {
                Write-Host 'NOT resolvable — run: wtw host sync' -ForegroundColor Red
            }

            Write-Host "  remote wtw    " -NoNewline
            $probe = Invoke-WtwRemoteCommand -HostEntry $entry -Arguments @('__aliases')
            if ($probe.Success) {
                $count = @($probe.Output | Where-Object { $_ }).Count
                Write-Host "reachable ($count registered targets)" -ForegroundColor Green
            } else {
                Write-Host "unreachable" -ForegroundColor Red
                if ($probe.Error) {
                    foreach ($line in (Format-WtwSshError -HostEntry $entry -ErrorText $probe.Error) -split "`n") {
                        Write-Host "    $line" -ForegroundColor DarkGray
                    }
                }
            }
            Write-Host ''
        }

        default {
            Write-Error "Unknown host action '$Action'. Use: list, add, remove, sync, trust, test."
        }
    }
}
