BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }

    # Shaped like real `tailscale status --json`: DNSName carries a trailing dot,
    # mobile devices report HostName as "localhost", and IPs are v4 + v6.
    $script:status = [PSCustomObject]@{
        MagicDNSSuffix = 'tailnet-example.ts.net'
        Self           = [PSCustomObject]@{
            HostName = 'Laptop'; DNSName = 'laptop.tailnet-example.ts.net.'
            OS = 'macOS'; Online = $true
            TailscaleIPs = @('100.64.0.12', 'fd7a:115c:a1e0::4e01:90bc')
        }
        Peer           = [PSCustomObject]@{
            k1 = [PSCustomObject]@{
                HostName = 'Workstation'; DNSName = 'workstation.tailnet-example.ts.net.'
                OS = 'windows'; Online = $false
                TailscaleIPs = @('100.64.0.10', 'fd7a:115c:a1e0::8e01:e5b6')
            }
            k2 = [PSCustomObject]@{
                HostName = 'Nas'; DNSName = 'nas.tailnet-example.ts.net.'
                OS = 'linux'; Online = $true
                TailscaleIPs = @('100.64.0.11')
            }
            k3 = [PSCustomObject]@{
                HostName = 'localhost'; DNSName = 'iphone181.tailnet-example.ts.net.'
                OS = 'iOS'; Online = $true
                TailscaleIPs = @('100.100.11.69')
            }
        }
    }
}

Describe 'ConvertFrom-WtwTailscaleOs' {
    It 'maps hostable operating systems to wtw platforms' {
        ConvertFrom-WtwTailscaleOs -Os 'macOS'   | Should -Be 'macos'
        ConvertFrom-WtwTailscaleOs -Os 'windows' | Should -Be 'windows'
        ConvertFrom-WtwTailscaleOs -Os 'linux'   | Should -Be 'linux'
    }

    It 'returns null for devices that cannot host a worktree' {
        # They are real tailnet members, so they must be recognised and skipped
        # rather than added and then failing at the first ssh.
        foreach ($os in 'iOS', 'android', 'tvOS', '') {
            ConvertFrom-WtwTailscaleOs -Os $os | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-WtwTailscalePeers' {
    BeforeAll { $script:peers = Get-WtwTailscalePeers -Raw $script:status }

    It 'returns self plus every peer' {
        $script:peers.Count | Should -Be 4
    }

    It 'names devices from DNSName, not HostName' {
        # Phones report HostName as "localhost"; only DNSName is unique.
        ($script:peers | Where-Object { $_.Os -eq 'iOS' }).Name | Should -Be 'iphone181'
    }

    It 'lower-cases names so they match wtw host keys' {
        ($script:peers | Where-Object { $_.Os -eq 'windows' }).Name | Should -Be 'workstation'
    }

    It 'offers the MagicDNS FQDN before the tailnet IPv4' {
        # The bare short name only resolves when the tailnet search domain is
        # configured; the FQDN always does.
        $troll = $script:peers | Where-Object { $_.Name -eq 'workstation' }
        $troll.Addresses[0] | Should -Be 'workstation.tailnet-example.ts.net'
        $troll.Addresses[1] | Should -Be '100.64.0.10'
    }

    It 'drops IPv6 addresses from the candidate list' {
        ($script:peers | Where-Object { $_.Name -eq 'workstation' }).Addresses |
            Should -Not -Contain 'fd7a:115c:a1e0::8e01:e5b6'
    }

    It 'flags this machine and carries online state' {
        ($script:peers | Where-Object { $_.IsSelf }).Name | Should -Be 'laptop'
        ($script:peers | Where-Object { $_.Name -eq 'workstation' }).Online | Should -BeFalse
        ($script:peers | Where-Object { $_.Name -eq 'nas' }).Online | Should -BeTrue
    }

    It 'returns an empty array when tailscale is absent' {
        Mock Get-WtwTailscaleCommand { $null }
        (Get-WtwTailscalePeers).Count | Should -Be 0
    }
}

Describe 'Resolve-WtwPeerPlan' {
    BeforeAll {
        $script:peers = Get-WtwTailscalePeers -Raw $script:status
        $script:hosts = Get-WtwHosts -Config ([PSCustomObject]@{
                hosts = [PSCustomObject]@{
                    workstation = [PSCustomObject]@{
                        aliases   = @('at')
                        user      = 'dev'
                        hostNames = @('workstation.local', '192.168.1.10')
                        platform  = 'windows'
                    }
                }
            })
        $script:plan = Resolve-WtwPeerPlan -Peers $script:peers -Hosts $script:hosts
    }

    It 'skips this machine' {
        ($script:plan | Where-Object { $_.Name -eq 'laptop' }).Action | Should -Be 'skip'
    }

    It 'skips phones with a reason naming the OS' {
        $phone = $script:plan | Where-Object { $_.Name -eq 'iphone181' }
        $phone.Action | Should -Be 'skip'
        $phone.Reason | Should -Match 'iOS'
    }

    It 'adds an unknown machine' {
        $new = $script:plan | Where-Object { $_.Name -eq 'nas' }
        $new.Action   | Should -Be 'add'
        $new.Platform | Should -Be 'linux'
    }

    It 'updates a known machine instead of duplicating it' {
        ($script:plan | Where-Object { $_.Name -eq 'workstation' }).Action | Should -Be 'update'
    }

    It 'puts tailnet addresses first and keeps the LAN ones as fallback' {
        # host sync writes the first candidate that answers. A tailnet name
        # resolves both on and off the LAN, so leading with it keeps the ssh
        # config valid when you change networks; .local stays behind it for when
        # Tailscale is down.
        $troll = $script:plan | Where-Object { $_.Name -eq 'workstation' }
        $troll.Addresses | Should -Be @(
            'workstation.tailnet-example.ts.net', '100.64.0.10',
            'workstation.local', '192.168.1.10'
        )
    }

    It 'matches an existing host by alias, not just by name' {
        $byAlias = Get-WtwHosts -Config ([PSCustomObject]@{
                hosts = [PSCustomObject]@{
                    winbox = [PSCustomObject]@{ aliases = @('workstation'); hostNames = @('10.0.0.9') }
                }
            })
        $plan = Resolve-WtwPeerPlan -Peers $script:peers -Hosts $byAlias
        ($plan | Where-Object { $_.Name -eq 'winbox' }).Action | Should -Be 'update'
    }

    It 'does not merge on a prefix match' {
        # Merging tailnet addresses into the wrong machine is worse than adding a
        # visible duplicate, so matching is exact-name-or-alias only.
        $prefixed = Get-WtwHosts -Config ([PSCustomObject]@{
                hosts = [PSCustomObject]@{ arctic = [PSCustomObject]@{ hostNames = @('10.0.0.9') } }
            })
        $plan = Resolve-WtwPeerPlan -Peers $script:peers -Hosts $prefixed
        ($plan | Where-Object { $_.Name -eq 'workstation' }).Action | Should -Be 'add'
    }

    It 'honours a persistent exclusion' {
        # A NAS or router lives on the tailnet forever; without persistence you
        # would decline it on every discover.
        $plan = Resolve-WtwPeerPlan -Peers $script:peers -Hosts $script:hosts -Ignore @('nas')
        $nas = $plan | Where-Object { $_.Name -eq 'nas' }
        $nas.Action | Should -Be 'skip'
        $nas.Reason | Should -Be 'excluded'
    }

    It 'reports nothing to do when the addresses are already present' {
        $already = Get-WtwHosts -Config ([PSCustomObject]@{
                hosts = [PSCustomObject]@{
                    workstation = [PSCustomObject]@{
                        hostNames = @('workstation.tailnet-example.ts.net', '100.64.0.10')
                        platform  = 'windows'
                    }
                }
            })
        $plan = Resolve-WtwPeerPlan -Peers $script:peers -Hosts $already
        ($plan | Where-Object { $_.Name -eq 'workstation' }).Action | Should -Be 'ok'
    }
}

Describe 'Get-WtwZeroTierNetworks' {
    It 'reports this node own managed addresses per network' {
        # The local ZeroTier client exposes only your own address and peer node
        # IDs — never member names or their managed IPs — so this is all wtw can
        # know without the ZeroTier Central API.
        $raw = @([PSCustomObject]@{
                id = '8056c2e21c000001'; name = 'home-net'
                assignedAddresses = @('10.147.20.128/24')
            })
        $networks = Get-WtwZeroTierNetworks -Raw $raw

        $networks.Count       | Should -Be 1
        $networks[0].Id       | Should -Be '8056c2e21c000001'
        $networks[0].Name     | Should -Be 'home-net'
        $networks[0].Addresses | Should -Contain '10.147.20.128/24'
    }
}
