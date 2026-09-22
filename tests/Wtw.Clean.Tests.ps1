BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking

    $script:NewWtwCleanTestRepo = {
        param([string] $Root)
        $repo = Join-Path $Root 'repo'
        New-Item -Path $repo -ItemType Directory -Force | Out-Null
        git -C $repo init -b main --quiet
        git -C $repo config user.email 'wtw@test.local'
        git -C $repo config user.name 'wtw test'
        'base' | Set-Content -Path (Join-Path $repo 'file.txt')
        git -C $repo add file.txt
        git -C $repo commit -m 'base' --quiet
        $repo
    }

    $script:AddWtwMergedBranch = {
        param([string] $Repo, [string] $Name, [string] $Text)
        git -C $Repo branch $Name
        git -C $Repo checkout $Name --quiet
        $Text | Set-Content -Path (Join-Path $Repo 'file.txt')
        git -C $Repo add file.txt
        git -C $Repo commit -m $Name --quiet
        git -C $Repo checkout main --quiet
        git -C $Repo merge $Name --quiet -m "merge $Name"
    }
}

Describe 'Resolve-WtwCleanScope' {
    It 'maps --all / --worktrees / --branches' {
        InModuleScope wtw {
            $all = Resolve-WtwCleanScope -All
            $all.Worktrees | Should -BeTrue
            $all.Branches | Should -BeTrue
            $all.Linked | Should -BeFalse

            $wt = Resolve-WtwCleanScope -Worktrees
            $wt.Worktrees | Should -BeTrue
            $wt.Branches | Should -BeFalse
            $wt.Linked | Should -BeFalse

            $br = Resolve-WtwCleanScope -Branches
            $br.Worktrees | Should -BeFalse
            $br.Branches | Should -BeTrue
            $br.Linked | Should -BeFalse
        }
    }

    It 'maps --linked without enabling the other sweeps' {
        InModuleScope wtw {
            $linked = Resolve-WtwCleanScope -Linked
            $linked.Worktrees | Should -BeFalse
            $linked.Branches | Should -BeFalse
            $linked.Linked | Should -BeTrue

            $extra = Resolve-WtwCleanScope -Extra
            $extra.Linked | Should -BeTrue
        }
    }

    It 'treats worktrees+branches as all' {
        InModuleScope wtw {
            $both = Resolve-WtwCleanScope -Worktrees -Branches
            $both.Worktrees | Should -BeTrue
            $both.Branches | Should -BeTrue
        }
    }

    It 'parses interactive tokens without Read-Host' {
        InModuleScope wtw {
            (Resolve-WtwCleanScope -Choice 'branches').Branches | Should -BeTrue
            (Resolve-WtwCleanScope -Choice '2').Branches | Should -BeTrue
            (Resolve-WtwCleanScope -Choice 'wt').Worktrees | Should -BeTrue
            (Resolve-WtwCleanScope -Choice 'linked').Linked | Should -BeTrue
            (Resolve-WtwCleanScope -Choice 'extra').Linked | Should -BeTrue
            $none = Resolve-WtwCleanScope -Choice 'none'
            $none | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-WtwMergedLocalBranches' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-clean-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
        $script:repo = & $script:NewWtwCleanTestRepo $script:tempDir
    }

    AfterEach {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'lists leftover merged branches and skips the default + checked-out worktree branches' {
        & $script:AddWtwMergedBranch $script:repo 'leftover' 'merged'
        & $script:AddWtwMergedBranch $script:repo 'held' 'held'
        $heldPath = Join-Path $script:tempDir 'held'
        git -C $script:repo worktree add $heldPath held --quiet

        InModuleScope wtw -Parameters @{ Repo = $script:repo } {
            (Get-WtwDefaultBranch -RepoPath $Repo) | Should -Be 'main'
            $found = Get-WtwMergedLocalBranches -RepoPath $Repo -RepoName 'demo'
            $found.DefaultBranch | Should -Be 'main'
            @($found.Items | ForEach-Object { $_.Branch }) | Should -Contain 'leftover'
            @($found.Items | ForEach-Object { $_.Branch }) | Should -Not -Contain 'held'
            @($found.Items | ForEach-Object { $_.Branch }) | Should -Not -Contain 'main'
            @($found.Skipped) | Should -Contain 'held'
        }
    }
}

Describe 'Invoke-WtwClean --branches' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-clean-inv-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
        $script:repo = & $script:NewWtwCleanTestRepo $script:tempDir
        & $script:AddWtwMergedBranch $script:repo 'leftover' 'merged'

        InModuleScope wtw -Parameters @{ TempDir = $script:tempDir; Repo = $script:repo } {
            $script:originalConfigPath = $script:WtwConfigPath
            $script:originalRegistryPath = $script:WtwRegistryPath
            $script:WtwConfigPath = Join-Path $TempDir 'config.json'
            $script:WtwRegistryPath = Join-Path $TempDir 'registry.json'

            [PSCustomObject]@{
                editor             = 'cursor'
                workspacesDir      = (Join-Path $TempDir 'ws')
                staleWorktreePaths = @((Join-Path $TempDir 'no-stale'))
            } | ConvertTo-Json -Depth 6 | Set-Content -Path $script:WtwConfigPath -Encoding utf8

            [PSCustomObject]@{
                repos = [PSCustomObject]@{
                    demo = [PSCustomObject]@{
                        mainPath  = $Repo
                        aliases   = @('dm')
                        worktrees = [PSCustomObject]@{}
                    }
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path $script:WtwRegistryPath -Encoding utf8
        }
    }

    AfterEach {
        InModuleScope wtw {
            $script:WtwConfigPath = $script:originalConfigPath
            $script:WtwRegistryPath = $script:originalRegistryPath
        }
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'dry-run lists leftover merged branches without deleting them' {
        $output = InModuleScope wtw {
            Invoke-WtwClean -Branches -DryRun 6>&1 | Out-String
        }
        $output | Should -Match 'leftover'
        $output | Should -Match 'dry-run'
        git -C $script:repo branch --list leftover | Should -Match 'leftover'
    }

    It 'force-deletes leftover merged branches with git branch -d' {
        InModuleScope wtw {
            Invoke-WtwClean -Branches -Force 6>&1 | Out-Null
        }
        git -C $script:repo branch --list leftover | Should -BeNullOrEmpty
        git -C $script:repo branch --show-current | Should -Be 'main'
    }

    It 'asks for a sweep when no scope flag is given' {
        InModuleScope wtw {
            Mock Read-Host { 'none' }
            $output = Invoke-WtwClean 6>&1 | Out-String
            $output | Should -Match 'Clean what'
            $output | Should -Match 'Cancelled'
            Should -Invoke Read-Host -Times 1 -Exactly
        }
        git -C $script:repo branch --list leftover | Should -Match 'leftover'
    }
}

Describe 'Get-WtwLinkedWorktreeItems' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-clean-linked-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
        $script:repo = & $script:NewWtwCleanTestRepo $script:tempDir
        git -C $script:repo branch leftover
        $script:unregisteredPath = Join-Path $script:tempDir 'unreg'
        $script:registeredPath = Join-Path $script:tempDir 'held'
        git -C $script:repo worktree add $script:unregisteredPath leftover --quiet
        git -C $script:repo worktree add -b held $script:registeredPath --quiet

        InModuleScope wtw -Parameters @{
            TempDir          = $script:tempDir
            Repo             = $script:repo
            UnregisteredPath = $script:unregisteredPath
            RegisteredPath   = $script:registeredPath
        } {
            $script:originalConfigPath = $script:WtwConfigPath
            $script:originalRegistryPath = $script:WtwRegistryPath
            $script:WtwConfigPath = Join-Path $TempDir 'config.json'
            $script:WtwRegistryPath = Join-Path $TempDir 'registry.json'

            [PSCustomObject]@{
                editor             = 'cursor'
                workspacesDir      = (Join-Path $TempDir 'ws')
                staleWorktreePaths = @((Join-Path $TempDir 'no-stale'))
            } | ConvertTo-Json -Depth 6 | Set-Content -Path $script:WtwConfigPath -Encoding utf8

            [PSCustomObject]@{
                repos = [PSCustomObject]@{
                    demo = [PSCustomObject]@{
                        mainPath  = $Repo
                        aliases   = @('dm')
                        worktrees = [PSCustomObject]@{
                            held = [PSCustomObject]@{
                                path   = $RegisteredPath
                                branch = 'held'
                            }
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
        }
        git -C $script:repo worktree remove --force $script:unregisteredPath 2>$null
        git -C $script:repo worktree remove --force $script:registeredPath 2>$null
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'lists unregistered extras and skips the primary checkout' {
        InModuleScope wtw -Parameters @{
            UnregisteredPath = $script:unregisteredPath
            RegisteredPath   = $script:registeredPath
            Repo             = $script:repo
        } {
            $found = @(Get-WtwLinkedWorktreeItems -Registry (Get-WtwRegistry) -IncludeUnregistered)
            $paths = @($found | ForEach-Object { Resolve-WtwRealPath $_.Path })
            $paths | Should -Contain (Resolve-WtwRealPath $UnregisteredPath)
            $paths | Should -Not -Contain (Resolve-WtwRealPath $Repo)
            $paths | Should -Not -Contain (Resolve-WtwRealPath $RegisteredPath)
            @($found | ForEach-Object { $_.Status }) | Should -Contain 'unregistered'
        }
    }

    It 'includes registered extras only when asked' {
        InModuleScope wtw -Parameters @{
            UnregisteredPath = $script:unregisteredPath
            RegisteredPath   = $script:registeredPath
        } {
            $found = @(Get-WtwLinkedWorktreeItems -Registry (Get-WtwRegistry) -IncludeRegistered -IncludeUnregistered)
            $paths = @($found | ForEach-Object { Resolve-WtwRealPath $_.Path })
            $paths | Should -Contain (Resolve-WtwRealPath $UnregisteredPath)
            $paths | Should -Contain (Resolve-WtwRealPath $RegisteredPath)
            $held = $found | Where-Object { Test-WtwSamePath $_.Path $RegisteredPath }
            $held.Status | Should -Be 'registered'
            $held.Task | Should -Be 'held'
        }
    }

    It 'skips the worktree the command is running from' {
        InModuleScope wtw -Parameters @{ UnregisteredPath = $script:unregisteredPath } {
            Push-Location $UnregisteredPath
            try {
                $found = @(Get-WtwLinkedWorktreeItems -Registry (Get-WtwRegistry) -IncludeUnregistered)
            } finally {
                Pop-Location
            }
            $paths = @($found | ForEach-Object { Resolve-WtwRealPath $_.Path })
            $paths | Should -Not -Contain (Resolve-WtwRealPath $UnregisteredPath)
        }
    }
}

Describe 'Invoke-WtwClean extra git worktrees' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-clean-extra-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
        $script:repo = & $script:NewWtwCleanTestRepo $script:tempDir
        git -C $script:repo branch leftover
        $script:unregisteredPath = Join-Path $script:tempDir 'unreg'
        $script:registeredPath = Join-Path $script:tempDir 'held'
        git -C $script:repo worktree add $script:unregisteredPath leftover --quiet
        git -C $script:repo worktree add -b held $script:registeredPath --quiet

        InModuleScope wtw -Parameters @{
            TempDir          = $script:tempDir
            Repo             = $script:repo
            RegisteredPath   = $script:registeredPath
        } {
            $script:originalConfigPath = $script:WtwConfigPath
            $script:originalRegistryPath = $script:WtwRegistryPath
            $script:WtwConfigPath = Join-Path $TempDir 'config.json'
            $script:WtwRegistryPath = Join-Path $TempDir 'registry.json'

            [PSCustomObject]@{
                editor             = 'cursor'
                workspacesDir      = (Join-Path $TempDir 'ws')
                staleWorktreePaths = @((Join-Path $TempDir 'no-stale'))
            } | ConvertTo-Json -Depth 6 | Set-Content -Path $script:WtwConfigPath -Encoding utf8

            [PSCustomObject]@{
                repos = [PSCustomObject]@{
                    demo = [PSCustomObject]@{
                        mainPath  = $Repo
                        aliases   = @('dm')
                        worktrees = [PSCustomObject]@{
                            held = [PSCustomObject]@{
                                path   = $RegisteredPath
                                branch = 'held'
                            }
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
        }
        git -C $script:repo worktree remove --force $script:unregisteredPath 2>$null
        git -C $script:repo worktree remove --force $script:registeredPath 2>$null
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'dry-run --worktrees lists unregistered extras but not registered ones' {
        $output = InModuleScope wtw {
            Invoke-WtwClean -Worktrees -DryRun 6>&1 | Out-String
        }
        $output | Should -Match 'unreg'
        $output | Should -Not -Match 'held'
        Test-Path $script:unregisteredPath | Should -BeTrue
        Test-Path $script:registeredPath | Should -BeTrue
    }

    It 'force --worktrees removes unregistered extras and keeps registered ones' {
        InModuleScope wtw {
            Invoke-WtwClean -Worktrees -Force 6>&1 | Out-Null
        }
        Test-Path $script:unregisteredPath | Should -BeFalse
        Test-Path $script:registeredPath | Should -BeTrue
        $wtList = git -C $script:repo worktree list --porcelain | Out-String
        $wtList | Should -Match 'held'
    }

    It 'dry-run --linked lists both registered and unregistered extras' {
        $output = InModuleScope wtw {
            Invoke-WtwClean -Linked -DryRun 6>&1 | Out-String
        }
        $output | Should -Match 'unreg'
        $output | Should -Match 'held'
        $output | Should -Match 'unregistered'
        $output | Should -Match 'registered'
    }

    It 'force --linked removes an unregistered extra git worktree' {
        InModuleScope wtw {
            Mock Remove-WtwWorktree {}
            $reg = Get-WtwRegistry
            $reg.repos.demo.worktrees = [PSCustomObject]@{}
            Save-WtwRegistry $reg
            Invoke-WtwClean -Linked -Force 6>&1 | Out-Null
        }
        Test-Path $script:unregisteredPath | Should -BeFalse
        Test-Path $script:registeredPath | Should -BeFalse
        git -C $script:repo worktree list --porcelain | Should -Not -Match 'unreg'
    }

    It 'force --linked tears down registered extras through wtw remove' {
        InModuleScope wtw {
            Mock Remove-WtwWorktree {}
            Invoke-WtwClean -Linked -Force 6>&1 | Out-Null
            Should -Invoke Remove-WtwWorktree -ParameterFilter { $Name -eq 'held' -and $Force } -Times 1
        }
        Test-Path $script:unregisteredPath | Should -BeFalse
    }
}
