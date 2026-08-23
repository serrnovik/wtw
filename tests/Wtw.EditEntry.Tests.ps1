BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'Rename-WtwObjectProperty' {
    It 'renames a note-property and keeps the others' {
        InModuleScope wtw {
            $obj = [PSCustomObject]@{
                keep = 1
                old  = 2
                last = 3
            }
            $renamed = Rename-WtwObjectProperty -Object $obj -OldName 'old' -NewName 'new'
            (Get-WtwPropertyNames -Object $renamed) | Should -Be @('keep', 'new', 'last')
            $renamed.new | Should -Be 2
            $renamed.keep | Should -Be 1
        }
    }
}

Describe 'Edit-WtwEntry' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "wtw-edit-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
        $script:wsPath = Join-Path $script:tempDir 'auth.code-workspace'
        [PSCustomObject]@{
            folders  = @([PSCustomObject]@{ path = '/tmp/demo_auth' })
            settings = [PSCustomObject]@{
                'wtw.managed'    = $true
                'wtw.prettyName' = '🟠 auth'
                'wtw.task'       = 'auth'
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:wsPath -Encoding utf8

        InModuleScope wtw -Parameters @{
            TempDir = $script:tempDir
            WsPath  = $script:wsPath
        } {
            $script:originalRegistryPath = $script:WtwRegistryPath
            $script:originalColorsPath = $script:WtwColorsPath
            $script:WtwRegistryPath = Join-Path $TempDir 'registry.json'
            $script:WtwColorsPath = Join-Path $TempDir 'colors.json'

            [PSCustomObject]@{
                repos = [PSCustomObject]@{
                    demo = [PSCustomObject]@{
                        mainPath  = '/tmp/demo'
                        aliases   = @('dm')
                        worktrees = [PSCustomObject]@{
                            auth = [PSCustomObject]@{
                                path       = '/tmp/demo_auth'
                                branch     = 'auth'
                                workspace  = $WsPath
                                color      = '#f18c29'
                                prettyName = '🟠 auth'
                            }
                            extra = [PSCustomObject]@{
                                path       = '/tmp/demo_extra'
                                branch     = 'extra'
                                color      = '#296ec8'
                                prettyName = '🔵 extra'
                            }
                        }
                    }
                    other = [PSCustomObject]@{
                        mainPath  = '/tmp/other'
                        aliases   = @('ot')
                        worktrees = [PSCustomObject]@{}
                    }
                }
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwRegistryPath -Encoding utf8

            [PSCustomObject]@{
                palette     = @('#f18c29', '#296ec8')
                assignments = [PSCustomObject]@{
                    'demo/auth'  = '#f18c29'
                    'demo/extra' = '#296ec8'
                    'demo/main'  = '#111111'
                    'other/main' = '#222222'
                }
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

    It 'prints the current worktree record when no fields are given' {
        $output = InModuleScope wtw {
            Mock Sync-WtwWorkspace {}
            Mock Add-WtwSourceGitRepository {}
            Edit-WtwEntry -Name 'auth' 6>&1 | Out-String
        }
        $output | Should -Match 'Worktree'
        $output | Should -Match 'Task\s+:\s+auth'
        $output | Should -Match '--name'
    }

    It 'updates a worktree pretty name and keeps the color circle' {
        InModuleScope wtw {
            Mock Sync-WtwWorkspace {}
            Mock Add-WtwSourceGitRepository {}
            Edit-WtwEntry -Name 'auth' -PrettyName 'Login flow' -NoSync
            $reg = Get-WtwRegistry
            $reg.repos.demo.worktrees.auth.prettyName | Should -Match 'Login flow'
            $reg.repos.demo.worktrees.auth.prettyName | Should -Match '🟠'
        }
    }

    It 'renames a worktree task key and the color assignment' {
        InModuleScope wtw {
            Mock Sync-WtwWorkspace {}
            Mock Add-WtwSourceGitRepository {}
            Edit-WtwEntry -Name 'auth' -Task 'login' -NoSync
            $reg = Get-WtwRegistry
            (Get-WtwPropertyNames -Object $reg.repos.demo.worktrees) | Should -Contain 'login'
            (Get-WtwPropertyNames -Object $reg.repos.demo.worktrees) | Should -Not -Contain 'auth'
            $reg.repos.demo.worktrees.login.prettyName | Should -Be '🟠 auth'

            $colors = Get-WtwColors
            (Get-WtwPropertyNames -Object $colors.assignments) | Should -Contain 'demo/login'
            (Get-WtwPropertyNames -Object $colors.assignments) | Should -Not -Contain 'demo/auth'
            $colors.assignments.'demo/login' | Should -Be '#f18c29'
        }
    }

    It 'refuses to reuse an existing worktree task key' {
        InModuleScope wtw {
            Mock Sync-WtwWorkspace {}
            Mock Add-WtwSourceGitRepository {}
            { Edit-WtwEntry -Name 'auth' -Task 'extra' -NoSync -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*already registered*'
        }
    }

    It 'replaces repo aliases' {
        InModuleScope wtw {
            Edit-WtwEntry -Name 'demo' -Alias 'sn,sm'
            $reg = Get-WtwRegistry
            (@($reg.repos.demo.aliases) -join ',') | Should -Be 'sn,sm'
        }
    }

    It 'renames a repo key and remaps color prefixes' {
        InModuleScope wtw {
            Edit-WtwEntry -Name 'demo' -Key 'snow'
            $reg = Get-WtwRegistry
            (Get-WtwPropertyNames -Object $reg.repos) | Should -Contain 'snow'
            (Get-WtwPropertyNames -Object $reg.repos) | Should -Not -Contain 'demo'
            $reg.repos.snow.aliases | Should -Contain 'dm'

            $colors = Get-WtwColors
            (Get-WtwPropertyNames -Object $colors.assignments) | Should -Contain 'snow/auth'
            (Get-WtwPropertyNames -Object $colors.assignments) | Should -Contain 'snow/main'
            (Get-WtwPropertyNames -Object $colors.assignments) | Should -Not -Contain 'demo/auth'
            $colors.assignments.'other/main' | Should -Be '#222222'
        }
    }

    It 'refuses --alias on a worktree' {
        InModuleScope wtw {
            { Edit-WtwEntry -Name 'auth' -Alias 'x' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*--alias is for repos*'
        }
    }

    It 'writes workspace identity before sync' {
        InModuleScope wtw {
            Mock Sync-WtwWorkspace { }
            Mock Add-WtwSourceGitRepository { }
            Mock Get-WtwCursorPrettyWorkspacePath { $WorkspacePath }
            Edit-WtwEntry -Name 'auth' -PrettyName 'Login flow' -Task 'login'
            $ws = Get-Content -Path $script:WtwRegistryPath -Raw | ConvertFrom-Json
            $savedWs = $ws.repos.demo.worktrees.login.workspace
            $file = Get-Content -Path $savedWs -Raw | ConvertFrom-Json
            $file.settings.'wtw.task' | Should -Be 'login'
            $file.settings.'wtw.prettyName' | Should -Match 'Login flow'
            Should -Invoke Sync-WtwWorkspace -Times 1 -Exactly
        }
    }
}

Describe 'Invoke-Wtw edit dispatch' {
    It 'routes edit and rename to Edit-WtwEntry' {
        InModuleScope wtw {
            Mock Edit-WtwEntry { }
            Mock Write-WtwUpdateNotice { }
            Invoke-Wtw 'edit' 'auth' '--name' 'Login' 6>&1 | Out-Null
            Should -Invoke Edit-WtwEntry -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'auth' -and $PrettyName -eq 'Login'
            }

            Invoke-Wtw 'rename' 'auth' 'Login' 6>&1 | Out-Null
            Should -Invoke Edit-WtwEntry -Times 2 -Exactly
        }
    }
}
