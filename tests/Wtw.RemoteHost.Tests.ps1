BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }

    $script:sampleConfig = [PSCustomObject]@{
        editor = 'cursor'
        hosts  = [PSCustomObject]@{
            arctictroll = [PSCustomObject]@{
                aliases        = @('at', 'troll')
                user           = 'sno'
                hostName       = '192.168.3.7'
                identityFile   = '~/.ssh/id_ed25519_arctictroll'
                identitiesOnly = $true
                platform       = 'windows'
            }
            snowpomme   = [PSCustomObject]@{
                aliases  = @('sp')
                user     = 'sno'
                hostName = '192.168.3.168'
                platform = 'macos'
            }
        }
    }
}

Describe 'Get-WtwHosts' {
    It 'reads hosts out of the user config' {
        $hosts = Get-WtwHosts -Config $script:sampleConfig
        $hosts.Count | Should -Be 2
        ($hosts | Where-Object { $_.Name -eq 'arctictroll' }).Platform | Should -Be 'windows'
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
        (Resolve-WtwHost -Name 'arctictroll' -Hosts $script:hosts).Name | Should -Be 'arctictroll'
    }

    It 'resolves by alias' {
        (Resolve-WtwHost -Name 'at' -Hosts $script:hosts).Name    | Should -Be 'arctictroll'
        (Resolve-WtwHost -Name 'troll' -Hosts $script:hosts).Name | Should -Be 'arctictroll'
    }

    It 'resolves an unambiguous prefix' {
        (Resolve-WtwHost -Name 'arctic' -Hosts $script:hosts).Name | Should -Be 'arctictroll'
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
        $names | Should -Contain 'arctictroll'
        $names | Should -Contain 'at'
        $names | Should -Contain 'sp'
    }
}

Describe 'Multi-address hosts' {
    BeforeAll {
        $script:multiConfig = [PSCustomObject]@{
            hosts = [PSCustomObject]@{
                snowpomme = [PSCustomObject]@{
                    aliases   = @('sp')
                    user      = 'sno'
                    hostNames = @('snowpomme.local', '192.168.3.168')
                    platform  = 'macos'
                }
            }
        }
    }

    It 'reads an ordered candidate list' {
        $entry = (Get-WtwHosts -Config $script:multiConfig)[0]
        $entry.HostNames | Should -Be @('snowpomme.local', '192.168.3.168')
        $entry.HostName  | Should -Be 'snowpomme.local'
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
        Mock Test-WtwAddressReachable { $Address -eq '192.168.3.168' }
        $block = New-WtwSshConfigBlock -Hosts (Get-WtwHosts -Config $script:multiConfig)

        $block | Should -Match 'HostName 192\.168\.3\.168'
        $block | Should -Match '# candidates: snowpomme\.local, 192\.168\.3\.168'
    }

    It 'falls back to the first candidate when the machine is asleep' {
        Mock Test-WtwAddressReachable { $false }
        $block = New-WtwSshConfigBlock -Hosts (Get-WtwHosts -Config $script:multiConfig)

        $block | Should -Match 'HostName snowpomme\.local'
        $block | Should -Match 'no candidate answered'
    }

    It 'reports which candidate answered' {
        Mock Test-WtwAddressReachable { $Address -eq 'snowpomme.local' }
        $resolved = Resolve-WtwHostAddress -HostEntry (Get-WtwHosts -Config $script:multiConfig)[0]

        $resolved.Address   | Should -Be 'snowpomme.local'
        $resolved.Reachable | Should -BeTrue
    }
}

Describe 'Format-WtwSshError' {
    BeforeAll {
        $script:entry = @{ Name = 'arctictroll'; User = 'sno'; HostName = 'arctictroll.local'
            HostNames = @('arctictroll.local', '192.168.3.7')
        }
    }

    It 'turns a host-key failure into the trust command' {
        # BatchMode=yes means ssh never offers its own interactive remedy, so the
        # raw one-liner is all the user would otherwise see.
        $msg = Format-WtwSshError -HostEntry $script:entry -ErrorText 'Host key verification failed.'
        $msg | Should -Match 'wtw host trust arctictroll'
        $msg | Should -Match 'new name'
    }

    It 'points a refused key at the identity option' {
        $msg = Format-WtwSshError -HostEntry $script:entry -ErrorText 'sno@x: Permission denied (publickey).'
        $msg | Should -Match '--identity'
    }

    It 'points an unresolvable name at host sync, listing the candidates' {
        $msg = Format-WtwSshError -HostEntry $script:entry -ErrorText 'ssh: Could not resolve hostname foo'
        $msg | Should -Match 'wtw host sync'
        $msg | Should -Match '192\.168\.3\.7'
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
        $block | Should -Match 'Host arctictroll at troll'
        $block | Should -Match 'HostName 192\.168\.3\.7'
        $block | Should -Match 'IdentityFile ~/\.ssh/id_ed25519_arctictroll'
        $block | Should -Match 'IdentitiesOnly yes'
    }

    It 'omits IdentitiesOnly when it was not requested' {
        $block = New-WtwSshConfigBlock -Hosts (Get-WtwHosts -Config $script:sampleConfig)
        ($block -split 'Host snowpomme')[1] | Should -Not -Match 'IdentitiesOnly'
    }

    It 'marks the fragment as managed' {
        $block = New-WtwSshConfigBlock -Hosts (Get-WtwHosts -Config $script:sampleConfig)
        $block | Should -Match 'Managed by wtw'
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
            (Get-Content $managed -Raw) | Should -Match 'Host arctictroll at troll'
        }
    }
}
