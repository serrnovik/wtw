BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'agentctl integration' {
    It 'defaults unknown repos to the team profile' {
        $profile = InModuleScope wtw {
            Get-WtwAgentCtlProfile -RepoName 'sample1' -RepoEntry ([PSCustomObject]@{}) -Config ([PSCustomObject]@{})
        }

        $profile | Should -Be 'team'
    }

    It 'uses the global agentctl default profile from config' {
        $config = [PSCustomObject]@{
            agentctl = [PSCustomObject]@{
                defaultProfile = 'solo'
            }
        }

        $profile = InModuleScope wtw -Parameters @{ Config = $config } {
            Get-WtwAgentCtlProfile -RepoName 'snowmain1' -RepoEntry ([PSCustomObject]@{}) -Config $Config
        }

        $profile | Should -Be 'solo'
    }

    It 'uses repo-specific profile config before the global default' {
        $config = [PSCustomObject]@{
            agentctl = [PSCustomObject]@{
                defaultProfile = 'team'
                repoProfiles   = [PSCustomObject]@{
                    snowmain1 = 'solo'
                }
            }
        }

        $profile = InModuleScope wtw -Parameters @{ Config = $config } {
            Get-WtwAgentCtlProfile -RepoName 'snowmain1' -RepoEntry ([PSCustomObject]@{}) -Config $Config
        }

        $profile | Should -Be 'solo'
    }

    It 'uses the repo registry profile before config defaults' {
        $repoEntry = [PSCustomObject]@{
            agentctlProfile = 'review'
        }
        $config = [PSCustomObject]@{
            agentctl = [PSCustomObject]@{
                defaultProfile = 'team'
                repoProfiles   = [PSCustomObject]@{
                    snowmain1 = 'solo'
                }
            }
        }

        $profile = InModuleScope wtw -Parameters @{ RepoEntry = $repoEntry; Config = $config } {
            Get-WtwAgentCtlProfile -RepoName 'snowmain1' -RepoEntry $RepoEntry -Config $Config
        }

        $profile | Should -Be 'review'
    }

    It 'sets a repo profile through the wtw agent command' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "wtw-agentctl-$([guid]::NewGuid())"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        try {
            $saved = InModuleScope wtw -Parameters @{ TempDir = $tempDir } {
                $script:WtwConfigDir = $TempDir
                $script:WtwConfigPath = Join-Path $TempDir 'config.json'

                Invoke-Wtw agent profile set demo-repo solo
                Get-Content -Path $script:WtwConfigPath -Raw | ConvertFrom-Json
            }

            $saved.agentctl.defaultProfile | Should -Be 'team'
            $saved.agentctl.repoProfiles.'demo-repo' | Should -Be 'solo'
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'resolves repo aliases when setting a profile' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "wtw-agentctl-$([guid]::NewGuid())"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        try {
            $saved = InModuleScope wtw -Parameters @{ TempDir = $tempDir } {
                $script:WtwConfigDir = $TempDir
                $script:WtwConfigPath = Join-Path $TempDir 'config.json'
                $script:WtwRegistryPath = Join-Path $TempDir 'registry.json'

                [PSCustomObject]@{
                    repos = [PSCustomObject]@{
                        sample1 = [PSCustomObject]@{
                            aliases = @('e1', 'evx1')
                        }
                    }
                } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwRegistryPath -Encoding utf8

                Invoke-Wtw agent profile set e1 team
                Get-Content -Path $script:WtwConfigPath -Raw | ConvertFrom-Json
            }

            $saved.agentctl.repoProfiles.sample1 | Should -Be 'team'
            $saved.agentctl.repoProfiles.PSObject.Properties.Name | Should -Not -Contain 'e1'
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
