BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'agentctl integration' {
    It 'defaults unknown repos to the team profile' {
        $profile = InModuleScope wtw {
            Get-WtwAgentCtlProfile -RepoName 'everix1' -RepoEntry ([PSCustomObject]@{}) -Config ([PSCustomObject]@{})
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
}
