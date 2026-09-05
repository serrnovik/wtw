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

            $wt = Resolve-WtwCleanScope -Worktrees
            $wt.Worktrees | Should -BeTrue
            $wt.Branches | Should -BeFalse

            $br = Resolve-WtwCleanScope -Branches
            $br.Worktrees | Should -BeFalse
            $br.Branches | Should -BeTrue
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
