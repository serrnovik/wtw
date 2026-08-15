BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }

    $script:sampleConfig = [PSCustomObject]@{
        editor = 'cursor'
        hosts  = [PSCustomObject]@{
            workstation = [PSCustomObject]@{
                aliases        = @('at', 'troll')
                user           = 'dev'
                hostName       = '192.168.1.10'
                identityFile   = '~/.ssh/id_ed25519_workstation'
                identitiesOnly = $true
                platform       = 'windows'
            }
            laptop   = [PSCustomObject]@{
                aliases  = @('sp')
                user     = 'dev'
                hostName = '192.168.1.11'
                platform = 'macos'
            }
        }
    }
}

Describe 'Get-WtwHosts' {
    It 'reads hosts out of the user config' {
        $hosts = Get-WtwHosts -Config $script:sampleConfig
        $hosts.Count | Should -Be 2
        ($hosts | Where-Object { $_.Name -eq 'workstation' }).Platform | Should -Be 'windows'
    }

    It 'defaults platform to linux and the remote command to wtw' {
        $config = [PSCustomObject]@{ hosts = [PSCustomObject]@{ box = [PSCustomObject]@{ user = 'x' } } }
        $entry = (Get-WtwHosts -Config $config)[0]
        $entry.Platform | Should -Be 'linux'
        $entry.Wtw      | Should -Be 'wtw'
    }

    It 'returns an empty list when no hosts are configured' {
        (Get-WtwHosts -Config ([PSCustomObject]@{ editor = 'cursor' })).Count | Should -Be 0
    }
}

Describe 'Resolve-WtwHost' {
    BeforeAll { $script:hosts = Get-WtwHosts -Config $script:sampleConfig }

    It 'resolves by exact name' {
        (Resolve-WtwHost -Name 'workstation' -Hosts $script:hosts).Name | Should -Be 'workstation'
    }

    It 'resolves by alias' {
        (Resolve-WtwHost -Name 'at' -Hosts $script:hosts).Name    | Should -Be 'workstation'
        (Resolve-WtwHost -Name 'troll' -Hosts $script:hosts).Name | Should -Be 'workstation'
    }

    It 'resolves an unambiguous prefix' {
        (Resolve-WtwHost -Name 'workst' -Hosts $script:hosts).Name | Should -Be 'workstation'
    }

    It 'refuses an ambiguous prefix rather than guessing a machine' {
        $ambiguous = Get-WtwHosts -Config ([PSCustomObject]@{
                hosts = [PSCustomObject]@{
                    build1 = [PSCustomObject]@{ user = 'a' }
                    build2 = [PSCustomObject]@{ user = 'b' }
                }
            })
        Resolve-WtwHost -Name 'build' -Hosts $ambiguous | Should -BeNullOrEmpty
    }

    It 'returns null for an unknown host' {
        Resolve-WtwHost -Name 'nope' -Hosts $script:hosts | Should -BeNullOrEmpty
    }
}

Describe 'Get-WtwHostNames' {
    It 'flattens names and aliases' {
        $names = Get-WtwHostNames -Hosts (Get-WtwHosts -Config $script:sampleConfig)
        $names | Should -Contain 'workstation'
        $names | Should -Contain 'at'
        $names | Should -Contain 'sp'
    }
}

Describe 'Multi-address hosts' {
    BeforeAll {
        $script:multiConfig = [PSCustomObject]@{
            hosts = [PSCustomObject]@{
                laptop = [PSCustomObject]@{
                    aliases   = @('sp')
                    user      = 'dev'
                    hostNames = @('laptop.local', '192.168.1.11')
                    platform  = 'macos'
                }
            }
        }
    }

    It 'reads an ordered candidate list' {
        $entry = (Get-WtwHosts -Config $script:multiConfig)[0]
        $entry.HostNames | Should -Be @('laptop.local', '192.168.1.11')
        $entry.HostName  | Should -Be 'laptop.local'
    }

    It 'still reads the pre-0.2 single hostName' {
        $legacy = [PSCustomObject]@{ hosts = [PSCustomObject]@{ box = [PSCustomObject]@{ hostName = '10.0.0.5' } } }
        $entry = (Get-WtwHosts -Config $legacy)[0]
        $entry.HostNames | Should -Be @('10.0.0.5')
        $entry.HostName  | Should -Be '10.0.0.5'
    }

    It 'writes the first reachable candidate into the ssh fragment' {
        # DHCP moves the IP; the .local name does not. Sync re-probes so the
        # config follows the machine instead of a stale address.
        Mock Test-WtwAddressReachable { $Address -eq '192.168.1.11' }
        $block = New-WtwSshConfigBlock -Hosts (Get-WtwHosts -Config $script:multiConfig)

        $block | Should -Match 'HostName 192\.168\.1\.11'
        $block | Should -Match '# candidates: laptop\.local, 192\.168\.1\.11'
    }

    It 'falls back to the first candidate when the machine is asleep' {
        Mock Test-WtwAddressReachable { $false }
        $block = New-WtwSshConfigBlock -Hosts (Get-WtwHosts -Config $script:multiConfig)

        $block | Should -Match 'HostName laptop\.local'
        $block | Should -Match 'no candidate answered'
    }

    It 'reports which candidate answered' {
        Mock Test-WtwAddressReachable { $Address -eq 'laptop.local' }
        $resolved = Resolve-WtwHostAddress -HostEntry (Get-WtwHosts -Config $script:multiConfig)[0]

        $resolved.Address   | Should -Be 'laptop.local'
        $resolved.Reachable | Should -BeTrue
    }
}

Describe 'Get-WtwAddressKind' {
    It 'recognises Tailscale by MagicDNS suffix and by CGNAT range' {
        Get-WtwAddressKind -Address 'workstation.tailnet-example.ts.net' | Should -Be 'tailscale'
        Get-WtwAddressKind -Address '100.64.0.10'               | Should -Be 'tailscale'
        Get-WtwAddressKind -Address '100.64.0.1'                    | Should -Be 'tailscale'
        Get-WtwAddressKind -Address '100.127.255.254'               | Should -Be 'tailscale'
    }

    It 'does not mistake a public 100.x address for Tailscale' {
        # 100.64.0.0/10 is second octet 64-127 only; 100.7.x is ordinary public space.
        Get-WtwAddressKind -Address '100.7.0.1'   | Should -Be 'other'
        Get-WtwAddressKind -Address '100.128.0.1' | Should -Be 'other'
    }

    It 'recognises mDNS and RFC1918' {
        Get-WtwAddressKind -Address 'laptop.local' | Should -Be 'mdns'
        Get-WtwAddressKind -Address '192.168.1.10'     | Should -Be 'lan'
        Get-WtwAddressKind -Address '172.16.0.9'      | Should -Be 'lan'
    }

    It 'recognises ZeroTier only from a subnet this machine joined' {
        # ZeroTier hands out ordinary RFC1918 addresses, so shape alone cannot
        # distinguish it from the LAN.
        Get-WtwAddressKind -Address '10.147.20.42' -ZeroTierPrefixes @('10.147.20.') | Should -Be 'zerotier'
        Get-WtwAddressKind -Address '10.147.20.42'                                    | Should -Be 'lan'
    }
}

Describe 'Get-WtwZeroTierPrefixes' {
    It 'turns an assigned address into a comparable /24 prefix' {
        $prefixes = Get-WtwZeroTierPrefixes -Networks @(@{ Addresses = @('10.147.20.128/24') })
        $prefixes | Should -Contain '10.147.20.'
    }
}

Describe 'Resolve-WtwHostAddress transport preference' {
    BeforeAll {
        $script:multi = @{
            Name = 'box'; Port = $null
            HostNames = @('box.tailnet-example.ts.net', 'box.local', '192.168.1.10')
        }
    }

    It 'takes the first reachable candidate when nothing is preferred' {
        Mock Test-WtwAddressReachable { $true }
        $r = Resolve-WtwHostAddress -HostEntry $script:multi
        $r.Address | Should -Be 'box.tailnet-example.ts.net'
        $r.Kind    | Should -Be 'tailscale'
    }

    It 'reorders to honour a via preference' {
        Mock Test-WtwAddressReachable { $true }
        $entry = $script:multi.Clone(); $entry.Via = 'lan'
        $r = Resolve-WtwHostAddress -HostEntry $entry
        $r.Address   | Should -Be '192.168.1.10'
        $r.Preferred | Should -BeTrue
    }

    It 'falls back rather than becoming unreachable when the preference is down' {
        # Pinning a transport must not strand the host when that transport is
        # unavailable — it reorders, it does not filter.
        Mock Test-WtwAddressReachable { $Address -eq 'box.tailnet-example.ts.net' }
        $entry = $script:multi.Clone(); $entry.Via = 'lan'
        $r = Resolve-WtwHostAddress -HostEntry $entry

        $r.Address   | Should -Be 'box.tailnet-example.ts.net'
        $r.Reachable | Should -BeTrue
        $r.Preferred | Should -BeFalse   # so the caller can say so
    }

    It 'treats via=any as no preference' {
        Mock Test-WtwAddressReachable { $true }
        $entry = $script:multi.Clone(); $entry.Via = 'any'
        (Resolve-WtwHostAddress -HostEntry $entry).Address | Should -Be 'box.tailnet-example.ts.net'
    }
}

Describe 'Format-WtwSshError' {
    BeforeAll {
        $script:entry = @{ Name = 'workstation'; User = 'dev'; HostName = 'workstation.local'
            HostNames = @('workstation.local', '192.168.1.10')
        }
    }

    It 'turns a host-key failure into the trust command' {
        # BatchMode=yes means ssh never offers its own interactive remedy, so the
        # raw one-liner is all the user would otherwise see.
        $msg = Format-WtwSshError -HostEntry $script:entry -ErrorText 'Host key verification failed.'
        $msg | Should -Match 'wtw host trust workstation'
        $msg | Should -Match 'new name'
    }

    It 'points a refused key at the identity option' {
        $msg = Format-WtwSshError -HostEntry $script:entry -ErrorText 'dev@x: Permission denied (publickey).'
        $msg | Should -Match '--identity'
    }

    It 'points an unresolvable name at host sync, listing the candidates' {
        $msg = Format-WtwSshError -HostEntry $script:entry -ErrorText 'ssh: Could not resolve hostname foo'
        $msg | Should -Match 'wtw host sync'
        $msg | Should -Match '192\.168\.1\.10'
    }

    It 'explains a missing remote pwsh and offers the --pwsh escape hatch' {
        foreach ($raw in 'zsh:1: command not found: pwsh', 'wtw-pwsh-not-found', "'pwsh' is not recognized") {
            $msg = Format-WtwSshError -HostEntry $script:entry -ErrorText $raw
            $msg | Should -Match 'non-login shell'
            $msg | Should -Match '--pwsh'
            $msg | Should -Match 'brew install powershell'
        }
    }

    It 'tells you the ssh server is off when the connection is refused' {
        # "Connection refused" means the host answered — it is the sshd that is
        # missing, which is a different fix from an unreachable machine.
        $msg = Format-WtwSshError -HostEntry $script:entry -ErrorText 'ssh: connect to host x port 22: Connection refused'
        $msg | Should -Match 'Remote Login'
        $msg | Should -Match 'Start-Service sshd'
    }

    It 'distinguishes a timeout from a refusal' {
        $msg = Format-WtwSshError -HostEntry $script:entry -ErrorText 'ssh: connect to host x port 22: Connection timed out'
        $msg | Should -Match 'awake'
        $msg | Should -Not -Match 'Remote Login'
    }

    It 'passes an unrecognised failure through verbatim' {
        Format-WtwSshError -HostEntry $script:entry -ErrorText 'kex_exchange_identification: boom' |
            Should -Match 'kex_exchange_identification: boom'
    }
}

Describe 'New-WtwSshConfigBlock' {
    It 'writes one Host line carrying the name and every alias' {
        # One block, not one per alias — so `ssh at` and ssh-remote+at both work.
        $block = New-WtwSshConfigBlock -Hosts (Get-WtwHosts -Config $script:sampleConfig)
        $block | Should -Match 'Host workstation at troll'
        $block | Should -Match 'HostName 192\.168\.1\.10'
        $block | Should -Match 'IdentityFile ~/\.ssh/id_ed25519_workstation'
        $block | Should -Match 'IdentitiesOnly yes'
    }

    It 'omits IdentitiesOnly when it was not requested' {
        # Pick the stanza by its Host line rather than by position: blocks are
        # emitted in name order, so an assertion keyed on "the second one" breaks
        # the moment a host is renamed.
        $block = New-WtwSshConfigBlock -Hosts (Get-WtwHosts -Config $script:sampleConfig)
        $stanza = @($block -split '(?m)^Host ' | Where-Object { $_ -match '^laptop sp' })

        $stanza.Count | Should -Be 1
        $stanza[0] | Should -Not -Match 'IdentitiesOnly'
    }

    It 'also emits every candidate address as its own Host pattern' {
        # Without HostName, so ssh uses the pattern itself as the address. This
        # is what lets `--via` target a raw address — and the editor's
        # ssh-remote+<address> authority — while still picking up User/IdentityFile.
        $block = New-WtwSshConfigBlock -Hosts (Get-WtwHosts -Config $script:sampleConfig)

        $block | Should -Match 'Host workstation\.local 192\.168\.1\.10|Host 192\.168\.1\.10'
        $direct = ($block -split 'Host ' | Where-Object { $_ -match '^\d|^workstation\.' })
        $direct | Should -Not -BeNullOrEmpty
    }

    It 'marks the fragment as managed' {
        $block = New-WtwSshConfigBlock -Hosts (Get-WtwHosts -Config $script:sampleConfig)
        $block | Should -Match 'Managed by wtw'
    }
}

Describe 'Get-WtwSshHostConflicts' {
    BeforeEach {
        $script:tmpConf = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-conf-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $script:tmpConf 'config.d') -Force | Out-Null
    }
    AfterEach { Remove-Item -Recurse -Force $script:tmpConf -ErrorAction SilentlyContinue }

    It 'finds other Host blocks that shadow a wtw-managed name' {
        # ssh takes the FIRST obtained value per keyword and wtw's fragment is
        # Included at the top, so a hand-written block further down still parses
        # but quietly follows wtw's HostName. Invisible unless reported.
        InModuleScope wtw -Parameters @{ Root = $script:tmpConf } {
            param($Root)
            $script:WtwSshConfigDir = $Root
            $script:WtwSshConfigPath = Join-Path $Root 'config'
            Set-Content -Path $script:WtwSshConfigPath -Value @(
                'Include config.d/wtw'
                'Host workstation'
                '  HostName 192.168.1.10'
                'Host other'
                'Host workstation 192.168.1.10'
            )
            Set-Content -Path (Join-Path $Root 'config.d' 'wtw') -Value @('Host workstation at', '  HostName ts')

            $conflicts = Get-WtwSshHostConflicts -Name 'workstation' -Aliases @('at')

            $conflicts.Count | Should -Be 2
            $conflicts[0].Line | Should -Be 2
            $conflicts[1].Line | Should -Be 5
        }
    }

    It 'never reports wtw own fragment as a conflict' {
        InModuleScope wtw -Parameters @{ Root = $script:tmpConf } {
            param($Root)
            $script:WtwSshConfigDir = $Root
            $script:WtwSshConfigPath = Join-Path $Root 'config'
            Set-Content -Path $script:WtwSshConfigPath -Value @('Include config.d/wtw')
            Set-Content -Path (Join-Path $Root 'config.d' 'wtw') -Value @('Host workstation at')

            (Get-WtwSshHostConflicts -Name 'workstation' -Aliases @('at')).Count | Should -Be 0
        }
    }

    It 'matches whole tokens, not substrings' {
        # `Host workstation2` is a different machine.
        InModuleScope wtw -Parameters @{ Root = $script:tmpConf } {
            param($Root)
            $script:WtwSshConfigDir = $Root
            $script:WtwSshConfigPath = Join-Path $Root 'config'
            Set-Content -Path $script:WtwSshConfigPath -Value @('Host workstation2', 'Host notat')

            (Get-WtwSshHostConflicts -Name 'workstation' -Aliases @('at')).Count | Should -Be 0
        }
    }
}

Describe 'Sync-WtwSshConfig' {
    BeforeEach {
        $script:tmpHome = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-ssh-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $script:tmpHome '.ssh') -Force | Out-Null
    }
    AfterEach {
        Remove-Item -Recurse -Force $script:tmpHome -ErrorAction SilentlyContinue
    }

    It 'prepends the Include so it is not scoped to an existing Host block' {
        # OpenSSH takes the first obtained value per keyword; an Include appended
        # after a `Host` block is parsed inside that block and applies to nothing else.
        InModuleScope wtw -Parameters @{ TmpHome = $script:tmpHome; Hosts = (Get-WtwHosts -Config $script:sampleConfig) } {
            param($TmpHome, $Hosts)
            $script:WtwSshConfigDir = Join-Path $TmpHome '.ssh'
            $script:WtwSshConfigPath = Join-Path $script:WtwSshConfigDir 'config'
            Set-Content -Path $script:WtwSshConfigPath -Value "Host github.com`n    User git`n"

            Sync-WtwSshConfig -Hosts $Hosts -Quiet | Out-Null

            $config = Get-Content -Path $script:WtwSshConfigPath -Raw
            $config.TrimStart() | Should -Match '^Include config\.d/wtw'
            $config | Should -Match 'Host github\.com'
        }
    }

    It 'is idempotent — a second sync does not add a second Include' {
        InModuleScope wtw -Parameters @{ TmpHome = $script:tmpHome; Hosts = (Get-WtwHosts -Config $script:sampleConfig) } {
            param($TmpHome, $Hosts)
            $script:WtwSshConfigDir = Join-Path $TmpHome '.ssh'
            $script:WtwSshConfigPath = Join-Path $script:WtwSshConfigDir 'config'
            Set-Content -Path $script:WtwSshConfigPath -Value "Host github.com`n"

            Sync-WtwSshConfig -Hosts $Hosts -Quiet | Out-Null
            Sync-WtwSshConfig -Hosts $Hosts -Quiet | Out-Null

            $config = Get-Content -Path $script:WtwSshConfigPath -Raw
            ([regex]::Matches($config, 'Include config\.d/wtw')).Count | Should -Be 1
        }
    }

    It 'creates ~/.ssh/config when it does not exist yet' {
        InModuleScope wtw -Parameters @{ TmpHome = $script:tmpHome; Hosts = (Get-WtwHosts -Config $script:sampleConfig) } {
            param($TmpHome, $Hosts)
            $script:WtwSshConfigDir = Join-Path $TmpHome '.ssh'
            $script:WtwSshConfigPath = Join-Path $script:WtwSshConfigDir 'config'

            $managed = Sync-WtwSshConfig -Hosts $Hosts -Quiet

            Test-Path $script:WtwSshConfigPath | Should -BeTrue
            Test-Path $managed | Should -BeTrue
            (Get-Content $managed -Raw) | Should -Match 'Host workstation at troll'
        }
    }
}
