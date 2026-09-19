BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'Format-WtwRepoDisplayName' {
    It 'prefixes a registry key when emoji is set' {
        InModuleScope wtw {
            Format-WtwRepoDisplayName -Name 'snowmain1' -Emoji '🎸' | Should -Be '🎸 snowmain1'
            Format-WtwRepoDisplayName -Name 'tn1-gitops' -Emoji '🎭 ☸️' | Should -Be '🎭 ☸️ tn1 gitops'
        }
    }

    It 'clears none / dash / empty' {
        InModuleScope wtw {
            ConvertTo-WtwNormalizedRepoEmoji 'none' | Should -BeNullOrEmpty
            ConvertTo-WtwNormalizedRepoEmoji '-' | Should -BeNullOrEmpty
            ConvertTo-WtwNormalizedRepoEmoji '  ' | Should -BeNullOrEmpty
            Format-WtwRepoDisplayName -Name 'kulissa-landing' -Emoji 'none' | Should -Be 'kulissa landing'
        }
    }

    It 'reads emoji from a repo entry' {
        InModuleScope wtw {
            $entry = [PSCustomObject]@{ emoji = '🎭 🪝'; mainPath = '/tmp/k' }
            Format-WtwRepoDisplayName -Name 'kulissa-GTM' -RepoEntry $entry | Should -Be '🎭 🪝 kulissa GTM'
            Get-WtwRepoEmoji -RepoEntry $entry | Should -Be '🎭 🪝'
        }
    }
}

Describe 'Edit-WtwEntry repo emoji' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-emoji-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null

        InModuleScope wtw -Parameters @{ TempDir = $script:tempDir } {
            $script:originalRegistryPath = $script:WtwRegistryPath
            $script:originalColorsPath = $script:WtwColorsPath
            $script:WtwRegistryPath = Join-Path $TempDir 'registry.json'
            $script:WtwColorsPath = Join-Path $TempDir 'colors.json'
            $script:WtwBackupRoot = Join-Path $TempDir 'backups'

            [PSCustomObject]@{
                repos = [PSCustomObject]@{
                    demo = [PSCustomObject]@{
                        mainPath  = '/tmp/demo'
                        aliases   = @('dm')
                        worktrees = [PSCustomObject]@{
                            auth = [PSCustomObject]@{
                                path       = '/tmp/demo_auth'
                                branch     = 'auth'
                                prettyName = '🟠 auth'
                            }
                        }
                    }
                }
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwRegistryPath -Encoding utf8

            [PSCustomObject]@{
                palette     = @('#111111')
                assignments = [PSCustomObject]@{ 'demo/main' = '#111111'; 'demo/auth' = '#f18c29' }
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwColorsPath -Encoding utf8
        }
    }

    AfterEach {
        InModuleScope wtw {
            $script:WtwRegistryPath = $script:originalRegistryPath
            $script:WtwColorsPath = $script:originalColorsPath
            $script:WtwBackupRoot = $null
        }
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'stores a repo emoji and allows it on a worktree' {
        InModuleScope wtw {
            Mock Sync-WtwSourceGitRepoDisplayName {}
            Mock Sync-WtwSourceGitWorktreeDisplayNames {}
            Edit-WtwEntry -Name 'demo' -Emoji '🎸' -NoSync
            $reg = Get-WtwRegistry
            $reg.repos.demo.emoji | Should -Be '🎸'
            Format-WtwRepoDisplayName -Name 'demo' -RepoEntry $reg.repos.demo | Should -Be '🎸 demo'

            Edit-WtwEntry -Name 'auth' -Emoji '🦔' -NoSync
            $reg = Get-WtwRegistry
            $reg.repos.demo.worktrees.auth.emoji | Should -Be '🦔'
            $reg.repos.demo.worktrees.auth.prettyName | Should -Be '🟠 auth'
        }
    }

    It 'clears a repo emoji with none' {
        InModuleScope wtw {
            Mock Sync-WtwSourceGitRepoDisplayName {}
            Edit-WtwEntry -Name 'demo' -Emoji '🎸' -NoSync
            Edit-WtwEntry -Name 'demo' -Emoji 'none' -NoSync
            $reg = Get-WtwRegistry
            (Get-WtwPropertyNames -Object $reg.repos.demo) | Should -Not -Contain 'emoji'
        }
    }

    It 'syncs SourceGit when emoji changes' {
        InModuleScope wtw {
            Mock Sync-WtwSourceGitRepoDisplayName {}
            Mock Sync-WtwSourceGitWorktreeDisplayNames {}
            Edit-WtwEntry -Name 'demo' -Emoji '🎸'
            Should -Invoke Sync-WtwSourceGitRepoDisplayName -Times 1 -Exactly
            Should -Invoke Sync-WtwSourceGitWorktreeDisplayNames -Times 1 -Exactly
        }
    }
}

Describe 'Invoke-Wtw --emoji without a value' {
    It 'rejects --emoji without a value on edit, create, and add' {
        InModuleScope wtw {
            Mock Edit-WtwEntry { }
            Mock New-WtwWorktree { }
            Mock Add-WtwEntry { }
            Mock Write-WtwUpdateNotice { }

            $editOutput = Invoke-Wtw 'edit' 'demo' '--emoji' 2>&1 | Out-String
            $editOutput | Should -Match '--emoji requires a value'
            Should -Invoke Edit-WtwEntry -Times 0 -Exactly

            $createOutput = Invoke-Wtw 'create' 'auth' '--emoji' 2>&1 | Out-String
            $createOutput | Should -Match '--emoji requires a value'
            Should -Invoke New-WtwWorktree -Times 0 -Exactly

            $addOutput = Invoke-Wtw 'add' '/tmp/demo_auth' '--emoji' 2>&1 | Out-String
            $addOutput | Should -Match '--emoji requires a value'
            Should -Invoke Add-WtwEntry -Times 0 -Exactly
        }
    }
}

Describe 'Resolve-WtwTerminalWorkspaceMetadata repo emoji' {
    It 'prefixes the registry key, not the first alias, for a main checkout' {
        InModuleScope wtw {
            Mock Get-WtwColors {
                [PSCustomObject]@{ assignments = [PSCustomObject]@{} }
            }

            $target = [PSCustomObject]@{
                RepoName      = 'snowmain1'
                TaskName      = $null
                WorktreeEntry = $null
                RepoEntry     = [PSCustomObject]@{
                    mainPath = (Join-Path ([System.IO.Path]::GetTempPath()) 'wtw-emoji-meta')
                    aliases  = @('sn1', 'sm')
                    emoji    = '🎸'
                }
            }

            $meta = Resolve-WtwTerminalWorkspaceMetadata -Target $target
            $meta.PrettyName | Should -Be '🎸 snowmain1'
            $meta.StatusValue | Should -Be 'snowmain1'
        }
    }

    It 'prepends a main-checkout color circle in front of the repo emoji' {
        InModuleScope wtw {
            Mock Get-WtwColors {
                [PSCustomObject]@{
                    assignments = [PSCustomObject]@{ 'snowmain1/main' = '#4BA532' }
                }
            }

            $target = [PSCustomObject]@{
                RepoName      = 'snowmain1'
                TaskName      = $null
                WorktreeEntry = $null
                RepoEntry     = [PSCustomObject]@{
                    mainPath = (Join-Path ([System.IO.Path]::GetTempPath()) 'wtw-emoji-meta')
                    emoji    = '🎸'
                }
            }

            $meta = Resolve-WtwTerminalWorkspaceMetadata -Target $target
            $meta.PrettyName | Should -Be '🟢 🎸 snowmain1'
            $meta.Color | Should -Be '#4BA532'
        }
    }

    It 'composes a worktree title from repo + derived glyphs' {
        InModuleScope wtw {
            $target = [PSCustomObject]@{
                RepoName      = 'snowmain1'
                TaskName      = 'feature'
                WorktreeEntry = [PSCustomObject]@{
                    path       = (Join-Path ([System.IO.Path]::GetTempPath()) 'wtw-emoji-meta-wt')
                    prettyName = 'Blue Feature'
                    color      = '#336699'
                }
                RepoEntry     = [PSCustomObject]@{
                    mainPath = (Join-Path ([System.IO.Path]::GetTempPath()) 'wtw-emoji-meta')
                    emoji    = '🎸'
                }
            }

            $expected = Format-WtwWorktreeDisplayName `
                -Name 'Blue Feature' `
                -TaskName 'feature' `
                -RepoEntry $target.RepoEntry
            $meta = Resolve-WtwTerminalWorkspaceMetadata -Target $target
            $meta.PrettyName | Should -Be $expected
            $meta.PrettyName | Should -Match '^🎸'
            $meta.PrettyName | Should -Match 'Blue Feature$'
            $meta.StatusValue | Should -Be 'snowmain1/feature'
        }
    }

    It 'humanizes a derived worktree slug and prefixes repo + worktree glyphs' {
        InModuleScope wtw {
            $target = [PSCustomObject]@{
                RepoName      = 'snowmain'
                TaskName      = 'NTB-real-dogfood'
                WorktreeEntry = [PSCustomObject]@{
                    path       = (Join-Path ([System.IO.Path]::GetTempPath()) 'wtw-emoji-ntb')
                    prettyName = '🔴 NTB-real-dogfood'
                    emoji      = '🐕'
                    color      = '#d93f0b'
                }
                RepoEntry     = [PSCustomObject]@{
                    mainPath = (Join-Path ([System.IO.Path]::GetTempPath()) 'wtw-emoji-snowmain')
                    emoji    = '🎸'
                }
            }

            $meta = Resolve-WtwTerminalWorkspaceMetadata -Target $target
            $meta.PrettyName | Should -Be '🎸🐕 NTB real dogfood'
        }
    }
}
