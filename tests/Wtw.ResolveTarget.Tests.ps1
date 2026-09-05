BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'Resolve-WtwTarget worktree aliases and branches' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-resolve-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null

        InModuleScope wtw -Parameters @{ TempDir = $script:tempDir } {
            $script:originalRegistryPath = $script:WtwRegistryPath
            $script:originalColorsPath = $script:WtwColorsPath
            $script:WtwRegistryPath = Join-Path $TempDir 'registry.json'
            $script:WtwColorsPath = Join-Path $TempDir 'colors.json'

            [PSCustomObject]@{
                repos = [PSCustomObject]@{
                    snowmain1 = [PSCustomObject]@{
                        mainPath  = '/tmp/snowmain1'
                        aliases   = @('sn1')
                        worktrees = [PSCustomObject]@{
                            't3code-ad4f13f1' = [PSCustomObject]@{
                                path       = '/tmp/t3code-ad4f13f1'
                                branch     = 't3code/pronouncefit-review-onboarding-video'
                                prettyName = '🟢 t3code-ad4f13f1'
                            }
                            auth = [PSCustomObject]@{
                                path       = '/tmp/snowmain1_auth'
                                branch     = 'auth'
                                prettyName = '🟠 auth'
                                aliases    = @('login flow')
                            }
                        }
                    }
                }
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwRegistryPath -Encoding utf8

            [PSCustomObject]@{
                palette     = @('#111111')
                assignments = [PSCustomObject]@{}
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwColorsPath -Encoding utf8
        }
    }

    AfterEach {
        InModuleScope wtw {
            $script:WtwRegistryPath = $script:originalRegistryPath
            $script:WtwColorsPath = $script:originalColorsPath
        }
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'matches a typed alias with spaces or hyphens' {
        InModuleScope wtw {
            (Resolve-WtwTarget 'login flow').TaskName | Should -Be 'auth'
            (Resolve-WtwTarget 'login-flow').TaskName | Should -Be 'auth'
            (Resolve-WtwTarget 'login').TaskName | Should -Be 'auth'
        }
    }

    It 'matches a branch substring after task and alias miss' {
        InModuleScope wtw {
            (Resolve-WtwTarget 'onboarding').TaskName | Should -Be 't3code-ad4f13f1'
            (Resolve-WtwTarget 'onboarding-video').TaskName | Should -Be 't3code-ad4f13f1'
        }
    }

    It 'prefers a worktree alias over a branch substring' {
        InModuleScope wtw {
            $reg = Get-WtwRegistry
            $reg.repos.snowmain1.worktrees.auth | Add-Member -NotePropertyName 'aliases' -NotePropertyValue @('onboarding') -Force
            Save-WtwRegistry $reg
            (Resolve-WtwTarget 'onboarding').TaskName | Should -Be 'auth'
        }
    }

    It 'reports ambiguity when two branches share a substring' {
        InModuleScope wtw {
            $reg = Get-WtwRegistry
            $reg.repos.snowmain1.worktrees | Add-Member -NotePropertyName 'extra' -NotePropertyValue ([PSCustomObject]@{
                    path       = '/tmp/extra'
                    branch     = 'feat/onboarding-copy'
                    prettyName = '🔵 extra'
                }) -Force
            Save-WtwRegistry $reg
            { Resolve-WtwTarget 'onboarding' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Ambiguous*'
        }
    }

    It 'joins leftover go words so unquoted aliases still resolve' {
        InModuleScope wtw {
            Mock Enter-WtwWorktree { }
            Mock Write-WtwUpdateNotice { }
            Invoke-Wtw 'go' 'login' 'flow' 6>&1 | Out-Null
            Should -Invoke Enter-WtwWorktree -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'login flow'
            }
        }
    }
}
