BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking

    $script:savedPaths = InModuleScope wtw {
        @{ Registry = $script:WtwRegistryPath; Colors = $script:WtwColorsPath }
    }

    $script:NewImportFixture = {
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-import-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -Path $temp -ItemType Directory -Force | Out-Null
        $origin = Join-Path $temp 'origin'
        $dirA = Join-Path $temp 'a'
        $dirB = Join-Path $temp 'b'
        New-Item -Path $dirA, $dirB -ItemType Directory -Force | Out-Null

        git init -b main --bare $origin --quiet
        $repoA = Join-Path $dirA 'demo'
        git init -b main $repoA --quiet
        git -C $repoA config user.email 'wtw@test.local'
        git -C $repoA config user.name 'wtw test'
        'base' | Set-Content -Path (Join-Path $repoA 'file.txt') -Encoding utf8
        git -C $repoA add file.txt
        git -C $repoA commit -m base --quiet
        git -C $repoA remote add origin $origin
        git -C $repoA push -u origin main --quiet 2>$null
        git -C $repoA checkout -b feature --quiet
        'feature' | Set-Content -Path (Join-Path $repoA 'file.txt') -Encoding utf8
        git -C $repoA add file.txt
        git -C $repoA commit -m feature --quiet
        git -C $repoA push -u origin feature --quiet 2>$null
        git -C $repoA checkout main --quiet
        $wtA = Join-Path $dirA 'demo_feature'
        git -C $repoA worktree add $wtA feature --quiet

        $repoB = Join-Path $dirB 'demo'
        git clone $origin $repoB --quiet 2>$null
        git -C $repoB config user.email 'wtw@test.local'
        git -C $repoB config user.name 'wtw test'

        [PSCustomObject]@{
            Temp   = $temp
            Origin = $origin
            DirA   = $dirA
            DirB   = $dirB
            RepoA  = $repoA
            RepoB  = $repoB
            WtA    = $wtA
            Commit = (git -C $wtA rev-parse HEAD).Trim()
        }
    }
}

AfterAll {
    InModuleScope wtw -Parameters @{ Saved = $script:savedPaths } {
        $script:WtwRegistryPath = $Saved.Registry
        $script:WtwColorsPath = $Saved.Colors
    }
}

Describe 'ConvertTo-WtwCanonicalGitUrl' {
    It 'treats ssh, https, and scp forms of one GitHub repo as the same target' {
        InModuleScope wtw {
            $urls = @(
                'git@github.com:Serrnovik/Snow.git'
                'https://github.com/serrnovik/Snow.git'
                'https://github.com/serrnovik/Snow'
                'ssh://git@github.com/serrnovik/Snow.git'
                'ssh://git@github.com:22/serrnovik/Snow.git'
            )
            $canon = @($urls | ForEach-Object { ConvertTo-WtwCanonicalGitUrl -Url $_ } | Select-Object -Unique)
            $canon.Count | Should -Be 1
            $canon[0] | Should -Be 'github.com/serrnovik/snow'
        }
    }
}

Describe 'import command help' {
    It 'documents --from as the host selector' {
        $out = & { Invoke-Wtw import --help } 6>&1 | Out-String
        $out | Should -Match 'wtw import --from <host> <name>'
        $out | Should -Match 'already checked out'
    }
}

Describe 'New-WtwRemoteExportScript' {
    It 'quotes a name that contains a single quote' {
        InModuleScope wtw {
            $script = New-WtwRemoteExportScript -Name "o'brien"
            $script | Should -Match "o''brien"
            $script | Should -Match 'Get-WtwWorktreeExport'
            $script | Should -Match 'wtw-export'
        }
    }
}

Describe 'wtw import snapshot' {
    BeforeEach {
        $script:fx = & $script:NewImportFixture
        $circle = [char]::ConvertFromUtf32(0x1F535)
        $registryPath = Join-Path $script:fx.Temp 'registry.json'
        [PSCustomObject]@{
            repos = [PSCustomObject]@{
                demo = [PSCustomObject]@{
                    mainPath       = $script:fx.RepoA
                    worktreeParent = $script:fx.DirA
                    aliases        = @('dm')
                    worktrees      = [PSCustomObject]@{
                        feature = [PSCustomObject]@{
                            path       = $script:fx.WtA
                            branch     = 'feature'
                            color      = '#112233'
                            prettyName = "$circle feature work"
                            emoji      = '🦔'
                            aliases    = @('onboarding')
                        }
                    }
                }
            }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $registryPath -Encoding utf8

        $script:export = InModuleScope wtw -Parameters @{ Temp = $script:fx.Temp } {
            $script:WtwRegistryPath = Join-Path $Temp 'registry.json'
            $script:WtwColorsPath = Join-Path $Temp 'colors.json'
            $raw = Get-WtwWorktreeExport -Name 'feature'
            ConvertFrom-WtwWorktreeExportText -Text ($raw | ConvertTo-Json -Compress -Depth 8)
        }

        [PSCustomObject]@{
            repos = [PSCustomObject]@{
                demo = [PSCustomObject]@{
                    mainPath       = $script:fx.RepoB
                    worktreeParent = $script:fx.DirB
                    aliases        = @('dm')
                    worktrees      = [PSCustomObject]@{}
                }
            }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $registryPath -Encoding utf8
    }

    AfterEach {
        if ($script:fx -and (Test-Path -LiteralPath $script:fx.Temp)) {
            Remove-Item -LiteralPath $script:fx.Temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'exports the branch, commit, color, emoji, and shared remote' {
        $script:export.kind | Should -Be 'wtw-export'
        $script:export.task | Should -Be 'feature'
        $script:export.branch | Should -Be 'feature'
        $script:export.commit | Should -Be $script:fx.Commit
        $script:export.color | Should -Be '#112233'
        $script:export.emoji | Should -Be '🦔'
        $script:export.folderSuffix | Should -Be 'feature'
        (@($script:export.aliases) -contains 'onboarding') | Should -BeTrue
        $script:export.detached | Should -BeFalse
        $script:export.dirty | Should -BeFalse

        InModuleScope wtw -Parameters @{ Export = $script:export; Origin = $script:fx.Origin } {
            $url = @($Export.remotes)[0].url
            (ConvertTo-WtwCanonicalGitUrl -Url $url) | Should -Be (ConvertTo-WtwCanonicalGitUrl -Url $Origin)
        }
    }

    It 'creates a worktree on the same branch and commit and keeps the settings' {
        $imported = Join-Path $script:fx.DirB 'demo_feature'
        InModuleScope wtw -Parameters @{ Export = $script:export } {
            Mock Initialize-WtwWorktreeMetadata { @{ Success = $true } }
            Import-WtwWorktreeSnapshot -Snapshot $Export -SourceName 'other' -ErrorAction Stop
            Should -Invoke Initialize-WtwWorktreeMetadata -Times 1 -ParameterFilter {
                $Task -eq 'feature' -and
                $Branch -eq 'feature' -and
                $Color -eq '#112233' -and
                "$Emoji" -eq '🦔' -and
                $PrettyName -eq 'feature work' -and
                @($Alias) -contains 'onboarding'
            }
        }
        Test-Path -LiteralPath $imported | Should -BeTrue
        (git -C $imported rev-parse HEAD).Trim() | Should -Be $script:fx.Commit
        (git -C $imported branch --show-current).Trim() | Should -Be 'feature'
    }

    It 'refuses when the branch is already checked out' {
        $held = Join-Path $script:fx.DirB 'held'
        git -C $script:fx.RepoB worktree add -b feature $held $script:fx.Commit --quiet
        $imported = Join-Path $script:fx.DirB 'demo_feature'
        InModuleScope wtw -Parameters @{ Export = $script:export } {
            Mock Initialize-WtwWorktreeMetadata { @{ Success = $true } }
            { Import-WtwWorktreeSnapshot -Snapshot $Export -SourceName 'other' -ErrorAction Stop } | Should -Throw '*already checked out*'
            Should -Invoke Initialize-WtwWorktreeMetadata -Times 0
        }
        Test-Path -LiteralPath $imported | Should -BeFalse
    }

    It 'refuses when no local clone shares the git remote' {
        git -C $script:fx.RepoB remote set-url origin (Join-Path $script:fx.Temp 'somewhere-else')
        InModuleScope wtw -Parameters @{ Export = $script:export } {
            Mock Initialize-WtwWorktreeMetadata { @{ Success = $true } }
            { Import-WtwWorktreeSnapshot -Snapshot $Export -SourceName 'other' -ErrorAction Stop } | Should -Throw '*No local repo shares a git remote*'
        }
    }

    It 'fast-forwards a local branch that is behind and not checked out' {
        $mainSha = (git -C $script:fx.RepoB rev-parse main).Trim()
        git -C $script:fx.RepoB branch feature $mainSha
        $imported = Join-Path $script:fx.DirB 'demo_feature'
        InModuleScope wtw -Parameters @{ Export = $script:export } {
            Mock Initialize-WtwWorktreeMetadata { @{ Success = $true } }
            Import-WtwWorktreeSnapshot -Snapshot $Export -SourceName 'other' -ErrorAction Stop
        }
        (git -C $imported rev-parse HEAD).Trim() | Should -Be $script:fx.Commit
    }

    It 'leaves a local branch alone when it is ahead of the other machine' {
        git -C $script:fx.RepoB checkout -b feature $script:fx.Commit --quiet
        'extra' | Set-Content -Path (Join-Path $script:fx.RepoB 'file.txt') -Encoding utf8
        git -C $script:fx.RepoB add file.txt
        git -C $script:fx.RepoB commit -m extra --quiet
        git -C $script:fx.RepoB checkout main --quiet
        $before = (git -C $script:fx.RepoB rev-parse feature).Trim()

        InModuleScope wtw -Parameters @{ Export = $script:export } {
            Mock Initialize-WtwWorktreeMetadata { @{ Success = $true } }
            { Import-WtwWorktreeSnapshot -Snapshot $Export -SourceName 'other' -ErrorAction Stop } | Should -Throw '*ahead*'
        }
        (git -C $script:fx.RepoB rev-parse feature).Trim() | Should -Be $before
    }

    It 'leaves a diverged local branch alone' {
        git -C $script:fx.RepoB checkout -b feature origin/main --quiet
        'side' | Set-Content -Path (Join-Path $script:fx.RepoB 'file.txt') -Encoding utf8
        git -C $script:fx.RepoB add file.txt
        git -C $script:fx.RepoB commit -m side --quiet
        git -C $script:fx.RepoB checkout main --quiet
        $before = (git -C $script:fx.RepoB rev-parse feature).Trim()

        InModuleScope wtw -Parameters @{ Export = $script:export } {
            { Import-WtwWorktreeSnapshot -Snapshot $Export -SourceName 'other' -ErrorAction Stop } | Should -Throw '*diverged*'
        }
        (git -C $script:fx.RepoB rev-parse feature).Trim() | Should -Be $before
    }

    It 'removes the new worktree when registration fails' {
        $imported = Join-Path $script:fx.DirB 'demo_feature'
        InModuleScope wtw -Parameters @{ Export = $script:export } {
            Mock Initialize-WtwWorktreeMetadata { @{ Success = $false } }
            Import-WtwWorktreeSnapshot -Snapshot $Export -SourceName 'other'
        }
        Test-Path -LiteralPath $imported | Should -BeFalse
    }

    It 'plans a fast-forward, an adopt, and a missing commit without writing' {
        InModuleScope wtw -Parameters @{ RepoB = $script:fx.RepoB; Commit = $script:fx.Commit } {
            (Get-WtwImportBranchPlan -RepoPath $RepoB -Branch 'feature' -Commit $Commit).Action | Should -Be 'create'
            git -C $RepoB branch feature $Commit
            (Get-WtwImportBranchPlan -RepoPath $RepoB -Branch 'feature' -Commit $Commit).Action | Should -Be 'adopt'
            git -C $RepoB branch -D feature | Out-Null
            $main = (git -C $RepoB rev-parse main).Trim()
            git -C $RepoB branch feature $main
            (Get-WtwImportBranchPlan -RepoPath $RepoB -Branch 'feature' -Commit $Commit).Action | Should -Be 'fast-forward'
            (Get-WtwImportBranchPlan -RepoPath $RepoB -Branch 'feature' -Commit ('a' * 40)).Action | Should -Be 'missing-commit'
        }
    }
}
