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
          discover [--yes] [--exclude a,b]  Find tailnet machines and register them
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
        (`laptop.local`) first and a last-known IP as backup: on DHCP — or
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
        wtw host add workstation --alias at --user dev --address 192.168.1.10 --platform windows --identity ~/.ssh/id_ed25519_workstation
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
        [string] $Wtw,
        [string] $Pwsh,
        [switch] $Yes,
        [string[]] $Exclude,
        [ValidateSet('tailscale', 'zerotier', 'mdns', 'lan', 'any')] [string] $Via
    )

    switch ($Action.ToLowerInvariant()) {
        'list' {
            $hosts = Get-WtwHosts
            if ($hosts.Count -eq 0) {
                Write-Host ''
                Write-Host '  No remote hosts configured.' -ForegroundColor Yellow
                Write-Host '  Add one:  wtw host add workstation --alias at --user dev --address 192.168.1.10 --platform windows' -ForegroundColor DarkGray
                Write-Host ''
                return
            }
            Write-Host ''
            $ztPrefixes = Get-WtwZeroTierPrefixes
            foreach ($h in ($hosts | Sort-Object { $_.Name })) {
                $aliases = if (@($h.Aliases).Count -gt 0) { " (" + (@($h.Aliases) -join ', ') + ")" } else { '' }
                # Which address ssh will actually use, and over which network —
                # "is this going over the tailnet or the LAN" is the first thing
                # you want to know and was previously invisible. Read from
                # `ssh -G`, so it reflects the merged config rather than what wtw
                # last intended to write.
                $effective = Get-WtwSshEffectiveHostName -Name $h.Name
                $known = if ($effective) { 'ssh ok' } else { 'not in ssh config — run: wtw host sync' }
                $knownColor = if ($effective) { 'DarkGray' } else { 'Yellow' }

                $active = if ($effective) { $effective } else { ($h.HostNames | Select-Object -First 1) }
                $kind = if ($active) { Get-WtwAddressKind -Address $active -ZeroTierPrefixes $ztPrefixes } else { '-' }

                Write-Host "  $($h.Name)$aliases" -ForegroundColor Cyan -NoNewline
                Write-Host "  $($h.User)@$active  [$($h.Platform)]" -ForegroundColor White -NoNewline
                Write-Host "  via $kind" -ForegroundColor Green -NoNewline
                Write-Host "  $known" -ForegroundColor $knownColor
                if (@($h.HostNames).Count -gt 1) {
                    $labelled = @($h.HostNames | ForEach-Object {
                            "$_ [$(Get-WtwAddressKind -Address $_ -ZeroTierPrefixes $ztPrefixes)]"
                        })
                    Write-Host "      candidates: $($labelled -join ', ')" -ForegroundColor DarkGray
                }
            }
            Write-Host ''
            Write-Host '  Details: wtw host show [name]' -ForegroundColor DarkGray
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
            if ($Pwsh)     { $entry | Add-Member -NotePropertyName 'pwsh' -NotePropertyValue $Pwsh -Force }
            if ($Via)      { $entry | Add-Member -NotePropertyName 'via' -NotePropertyValue $Via -Force }
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

        'discover' {
            # No @() wrapper — these return `,@(...)` already; re-wrapping nests
            # the array and every $item.Property would read the wrapper.
            $peers = Get-WtwTailscalePeers
            if ($peers.Count -eq 0) {
                Write-Host ''
                Write-Host '  No tailnet found.' -ForegroundColor Yellow
                if (-not (Get-WtwTailscaleCommand)) {
                    Write-Host '  The tailscale CLI is not installed here. https://tailscale.com/download' -ForegroundColor DarkGray
                } else {
                    Write-Host '  tailscale is installed but reported nothing — is it logged in and up?' -ForegroundColor DarkGray
                    Write-Host '    tailscale status' -ForegroundColor DarkGray
                }
                Show-WtwZeroTierHint
                return
            }

            # Exclusions persist. A NAS or a router is on the tailnet forever, so
            # a one-shot flag would mean re-declining it on every discover.
            $config = Get-WtwConfig
            $ignored = @(Get-WtwPropertyValue -Object $config -Name 'discoverIgnore' -DefaultValue @())
            if ($Exclude) {
                $ignored = @($ignored + (Split-WtwAliasList -Value $Exclude)) | Select-Object -Unique
                if (-not $config) { $config = New-WtwDefaultConfig }
                $config | Add-Member -NotePropertyName 'discoverIgnore' -NotePropertyValue @($ignored) -Force
                Save-WtwConfig $config
                Write-Host "  Ignoring from now on: $((@($ignored)) -join ', ')" -ForegroundColor DarkGray
            }

            $existingHosts = Get-WtwHosts
            $plan = Resolve-WtwPeerPlan -Peers $peers -Hosts $existingHosts -Ignore $ignored

            Write-Host ''
            Write-Host '  Tailnet machines' -ForegroundColor Cyan
            Write-Host ''
            foreach ($item in $plan) {
                $color = switch ($item.Action) {
                    'add' { 'Green' } 'update' { 'Yellow' } 'ok' { 'DarkGray' } default { 'DarkGray' }
                }
                $state = if ($item.Online) { 'online ' } else { 'offline' }
                Write-Host ("    {0,-8} {1,-24} {2,-8} {3,-8} {4}" -f $item.Action, $item.Name, ($item.Platform ?? '-'), $state, $item.Reason) -ForegroundColor $color
                if ($item.AddAddresses.Count -gt 0) {
                    Write-Host ("             + " + (@($item.AddAddresses) -join ', ')) -ForegroundColor DarkGray
                }
            }
            Write-Host ''

            $actionable = @($plan | Where-Object { $_.Action -in @('add', 'update') })
            if ($actionable.Count -eq 0) {
                Write-Host '  Nothing to change.' -ForegroundColor Green
                Show-WtwZeroTierHint
                return
            }

            # Tailscale knows the machine but not which account you ssh in as.
            $sshUser = if ($User) { $User } elseif ($env:USER) { $env:USER } else { $env:USERNAME }
            Write-Host "  New hosts will use ssh user '$sshUser' (override with --user)." -ForegroundColor DarkGray

            if (-not $Yes) {
                $answer = Read-Host "  Apply these $($actionable.Count) change(s)? [y/N]"
                if ($answer -notin @('y', 'Y', 'yes')) {
                    Write-Host '  No changes made.' -ForegroundColor DarkGray
                    return
                }
            }

            $config = Get-WtwConfig
            if (-not $config) { $config = New-WtwDefaultConfig }
            $hostMap = Get-WtwPropertyValue -Object $config -Name 'hosts'
            if (-not $hostMap) { $hostMap = [PSCustomObject]@{} }

            foreach ($item in $actionable) {
                $entry = Get-WtwPropertyValue -Object $hostMap -Name $item.Name
                if (-not $entry) { $entry = [PSCustomObject]@{} }

                $entry | Add-Member -NotePropertyName 'hostNames' -NotePropertyValue @($item.Addresses) -Force
                if ((Get-WtwPropertyNames -Object $entry) -contains 'hostName') {
                    $entry.PSObject.Properties.Remove('hostName')
                }
                if ($item.Action -eq 'add') {
                    $entry | Add-Member -NotePropertyName 'user' -NotePropertyValue $sshUser -Force
                    $entry | Add-Member -NotePropertyName 'platform' -NotePropertyValue $item.Platform -Force
                } elseif (-not (Get-WtwPropertyValue -Object $entry -Name 'platform')) {
                    $entry | Add-Member -NotePropertyName 'platform' -NotePropertyValue $item.Platform -Force
                }

                $hostMap | Add-Member -NotePropertyName $item.Name -NotePropertyValue $entry -Force
                Write-Host "  $($item.Action): $($item.Name)" -ForegroundColor Green
            }

            $config | Add-Member -NotePropertyName 'hosts' -NotePropertyValue $hostMap -Force
            Save-WtwConfig $config
            Sync-WtwSshConfig | Out-Null

            Write-Host ''
            Write-Host '  Next:  wtw host trust <name>   then   wtw host test <name>' -ForegroundColor DarkGray
            Write-Host '  Aliases are not invented for you — add one with: wtw host add <name> --alias <a>' -ForegroundColor DarkGray
            Write-Host ''
            Show-WtwZeroTierHint
        }

        { $_ -in 'show', 'info' } {
            $targets = if ($Name) {
                $entry = Resolve-WtwHost -Name $Name
                if (-not $entry) { Write-Error "Host '$Name' is not configured. See: wtw host list"; return }
                @($entry)
            } else {
                Get-WtwHosts
            }
            if (@($targets).Count -eq 0) {
                Write-Host ''
                Write-Host '  No remote hosts configured.  Try: wtw host discover' -ForegroundColor Yellow
                Write-Host ''
                return
            }

            $ztPrefixes = Get-WtwZeroTierPrefixes
            foreach ($h in @($targets)) {
                $resolved = Resolve-WtwHostAddress -HostEntry $h
                $port = if ($h.Port) { [int]$h.Port } else { 22 }

                Write-Host ''
                Write-Host "  $($h.Name)" -ForegroundColor Cyan -NoNewline
                if (@($h.Aliases).Count -gt 0) { Write-Host "  (aliases: $((@($h.Aliases)) -join ', '))" -ForegroundColor DarkGray } else { Write-Host '' }

                Write-Host "    ssh          $($h.User)@$($resolved.Address)  port $port" -ForegroundColor White
                Write-Host "    platform     $($h.Platform)" -ForegroundColor White
                if ($h.IdentityFile) { Write-Host "    identity     $($h.IdentityFile)" -ForegroundColor White }
                if ($h.Pwsh)         { Write-Host "    pwsh         $($h.Pwsh)" -ForegroundColor White }
                if ($h.Wtw -and $h.Wtw -ne 'wtw') { Write-Host "    wtw command  $($h.Wtw)" -ForegroundColor White }

                # NOT $via: PowerShell variable names are case-insensitive, so
                # assigning $via rebinds the $Via parameter and trips its
                # ValidateSet on an empty value.
                $preferredVia = Get-WtwPropertyValue -Object $h -Name 'Via'
                $viaLabel = if ($preferredVia -and $preferredVia -ne 'any') { $preferredVia } else { 'any (first reachable wins)' }
                Write-Host "    prefer       $viaLabel" -ForegroundColor White

                Write-Host '    addresses' -ForegroundColor White
                foreach ($candidate in @($h.HostNames)) {
                    $kind = Get-WtwAddressKind -Address $candidate -ZeroTierPrefixes $ztPrefixes
                    $up = Test-WtwAddressReachable -Address $candidate -Port $port
                    $active = if ($candidate -eq $resolved.Address) { '→' } else { ' ' }
                    $state = if ($up) { 'up  ' } else { 'down' }
                    $color = if ($candidate -eq $resolved.Address) { 'Green' } elseif ($up) { 'White' } else { 'DarkGray' }
                    Write-Host ("      {0} {1,-10} {2}  {3}" -f $active, $kind, $state, $candidate) -ForegroundColor $color
                }
                if ($preferredVia -and $preferredVia -ne 'any' -and -not $resolved.Preferred) {
                    Write-Host "      note: '$preferredVia' was preferred but is not reachable — using $($resolved.Kind)." -ForegroundColor Yellow
                }

                $conflicts = Get-WtwSshHostConflicts -Name $h.Name -Aliases $h.Aliases
                if ($conflicts.Count -gt 0) {
                    Write-Host "    ssh config   $($conflicts.Count) other Host block(s) also match this name:" -ForegroundColor Yellow
                    foreach ($conflict in $conflicts) {
                        Write-Host "                 $($conflict.File):$($conflict.Line)" -ForegroundColor DarkGray
                    }
                }
            }
            Write-Host ''
            Write-Host '  Change one:  wtw host add <name> --via tailscale|lan|mdns|zerotier|any' -ForegroundColor DarkGray
            Write-Host '  Deep check:  wtw host test <name>' -ForegroundColor DarkGray
            Write-Host ''
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

            $conflicts = Get-WtwSshHostConflicts -Name $entry.Name -Aliases $entry.Aliases
            if ($conflicts.Count -gt 0) {
                Write-Host "  other blocks  " -NoNewline
                Write-Host "$($conflicts.Count) more Host block(s) match this name" -ForegroundColor Yellow
                foreach ($conflict in $conflicts) {
                    Write-Host "                  $($conflict.File):$($conflict.Line)  $($conflict.Text)" -ForegroundColor DarkGray
                }
                Write-Host "                  wtw's block is Included first, so its HostName/User/IdentityFile win." -ForegroundColor DarkGray
                Write-Host "                  Harmless if they point at the same machine — but they now follow wtw." -ForegroundColor DarkGray
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
            Write-Error "Unknown host action '$Action'. Use: list, discover, add, remove, sync, trust, test."
        }
    }
}
