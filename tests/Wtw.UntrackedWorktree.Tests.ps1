BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'Untracked git worktrees' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-untracked-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
        $script:repo = Join-Path $script:tempDir 'demo'
        New-Item -Path $script:repo -ItemType Directory -Force | Out-Null
        git -C $script:repo init -b main --quiet
        git -C $script:repo config user.email 'wtw@test.local'
        git -C $script:repo config user.name 'wtw test'
        'base' | Set-Content -Path (Join-Path $script:repo 'file.txt')
        git -C $script:repo add file.txt
        git -C $script:repo commit -m 'base' --quiet

        $script:tracked = Join-Path $script:tempDir 'demo_tracked'
        $script:agent = Join-Path $script:tempDir 'demo_agent-task'
        git -C $script:repo worktree add -b tracked $script:tracked --quiet 2>$null
        git -C $script:repo worktree add -b t3/agent-branch $script:agent --quiet 2>$null

        InModuleScope wtw -Parameters @{ TempDir = $script:tempDir; Repo = $script:repo; Tracked = $script:tracked } {
            $script:originalConfigPath = $script:WtwConfigPath
            $script:originalRegistryPath = $script:WtwRegistryPath
            $script:originalColorsPath = $script:WtwColorsPath
            $script:WtwConfigPath = Join-Path $TempDir 'config.json'
            $script:WtwRegistryPath = Join-Path $TempDir 'registry.json'
            $script:WtwColorsPath = Join-Path $TempDir 'colors.json'

            [PSCustomObject]@{ editor = 'code'; workspacesDir = (Join-Path $TempDir 'ws') } |
                ConvertTo-Json -Depth 6 | Set-Content -Path $script:WtwConfigPath -Encoding utf8
            [PSCustomObject]@{ assignments = [PSCustomObject]@{ 'demo/tracked' = '#112233'; 'demo/other' = '#445566' } } |
                ConvertTo-Json -Depth 6 | Set-Content -Path $script:WtwColorsPath -Encoding utf8
            [PSCustomObject]@{
                repos = [PSCustomObject]@{
                    demo = [PSCustomObject]@{
                        mainPath  = $Repo
                        templateWorkspace = $null
                        aliases   = @('dm')
                        worktrees = [PSCustomObject]@{
                            tracked = [PSCustomObject]@{ path = $Tracked; branch = 'tracked'; color = '#112233'; workspace = $null; created = '2026-01-01' }
                        }
                    }
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path $script:WtwRegistryPath -Encoding utf8
        }
    }

    AfterEach {
        InModuleScope wtw {
            $script:WtwConfigPath = $script:originalConfigPath
            $script:WtwRegistryPath = $script:originalRegistryPath
            $script:WtwColorsPath = $script:originalColorsPath
        }
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'finds git worktrees the registry does not track' {
        InModuleScope wtw {
            $found = @(Get-WtwUntrackedWorktree -Registry (Get-WtwRegistry))
            $found.Count | Should -Be 1
            $found[0].RepoName | Should -Be 'demo'
            $found[0].TaskName | Should -Be 'agent-task'
            $found[0].Branch | Should -Be 't3/agent-branch'
        }
    }

    It 'matches an untracked worktree by folder or branch' {
        InModuleScope wtw {
            $registry = Get-WtwRegistry
            @(Find-WtwUntrackedWorktree -Registry $registry -Name 'agent').Count | Should -Be 1
            @(Find-WtwUntrackedWorktree -Registry $registry -Name 't3/agent-branch').Count | Should -Be 1
            @(Find-WtwUntrackedWorktree -Registry $registry -Name 'nothing-like-it').Count | Should -Be 0
        }
    }

    It 'shows untracked worktrees in wtw list and hides them with -NoUntracked' {
        $shown = InModuleScope wtw { Get-WtwList -Wide 6>&1 | Out-String }
        $shown | Should -Match 'agent-task'
        $shown | Should -Match 'does not track yet'
        $hidden = InModuleScope wtw { Get-WtwList -Wide -NoUntracked 6>&1 | Out-String }
        $hidden | Should -Not -Match 'agent-task'
    }

    It 'does not adopt without -AdoptUntracked' {
        InModuleScope wtw {
            Mock Add-WtwEntry { }
            $target = Resolve-WtwTarget -Name 'agent-task' -SkipFuzzy -ErrorAction SilentlyContinue
            $target | Should -BeNullOrEmpty
            Should -Invoke Add-WtwEntry -Times 0 -Exactly
        }
    }

    It 'adopts an untracked worktree when a command acts on it' {
        InModuleScope wtw -Parameters @{ Agent = $script:agent } {
            Mock Add-WtwEntry {
                $registry = Get-WtwRegistry
                $registry.repos.$Repo.worktrees |
                    Add-Member -NotePropertyName $Task -NotePropertyValue ([PSCustomObject]@{ path = $Path; branch = 't3/agent-branch' })
                Save-WtwRegistry $registry
            }
            $target = Resolve-WtwTarget -Name 'agent' -AdoptUntracked 6>$null
            $target.RepoName | Should -Be 'demo'
            $target.TaskName | Should -Be 'agent-task'
            Should -Invoke Add-WtwEntry -Times 1 -Exactly -ParameterFilter {
                $Task -eq 'agent-task' -and $Repo -eq 'demo' -and (Split-Path $Path -Leaf) -eq (Split-Path $Agent -Leaf)
            }
        }
    }

    It 'removes registry entries for worktrees git already removed' {
        git -C $script:repo worktree remove $script:tracked --force
        InModuleScope wtw {
            $removed = @(Remove-WtwGoneWorktree -Registry (Get-WtwRegistry))
            $removed | Should -Be @('demo/tracked')
            (Get-WtwPropertyNames -Object (Get-WtwRegistry).repos.demo.worktrees) | Should -Not -Contain 'tracked'
            $assigned = Get-WtwPropertyNames -Object (Get-WtwColors).assignments
            $assigned | Should -Not -Contain 'demo/tracked'
            $assigned | Should -Contain 'demo/other'
        }
    }

    It 'keeps a registered worktree whose folder still exists' {
        InModuleScope wtw {
            @(Remove-WtwGoneWorktree -Registry (Get-WtwRegistry)).Count | Should -Be 0
            (Get-WtwPropertyNames -Object (Get-WtwRegistry).repos.demo.worktrees) | Should -Contain 'tracked'
        }
    }

    It 'keeps a missing folder git still lists as a live worktree' {
        InModuleScope wtw -Parameters @{ Repo = $script:repo } {
            $offline = Join-Path $Repo 'nowhere-offline'
            Mock Get-WtwGitWorktreeList {
                @(
                    [pscustomobject]@{ Path = $Repo; Prunable = $false; Bare = $false; Detached = $false; Branch = 'main' }
                    [pscustomobject]@{ Path = $offline; Prunable = $false; Bare = $false; Detached = $false; Branch = 'offline' }
                )
            }
            $registry = Get-WtwRegistry
            $registry.repos.demo.worktrees | Add-Member -NotePropertyName offline -NotePropertyValue ([PSCustomObject]@{ path = $offline })
            @(Remove-WtwGoneWorktree -Registry $registry).Count | Should -Be 0
        }
    }
}
