BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'SourceGit nested nodes and backups' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-sg-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
        $script:prefPath = Join-Path $script:tempDir 'preference.json'
        $script:originalPref = $env:WTW_SOURCEGIT_PREF
        $env:WTW_SOURCEGIT_PREF = $script:prefPath

        $prefs = [PSCustomObject]@{
            RepositoryNodes = @(
                [PSCustomObject]@{
                    Id           = '/tmp/group'
                    Name         = 'demo'
                    IsRepository = $false
                    SubNodes     = @(
                        [PSCustomObject]@{
                            Id           = '/tmp/demo_auth'
                            Name         = '🟠 auth'
                            IsRepository = $true
                            Bookmark     = 2
                            SubNodes     = @()
                        }
                    )
                }
            )
        }
        $prefs | ConvertTo-Json -Depth 20 | Set-Content -Path $script:prefPath -Encoding utf8
    }

    AfterEach {
        $env:WTW_SOURCEGIT_PREF = $script:originalPref
        InModuleScope wtw {
            $script:WtwBackupRoot = $null
        }
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'updates a nested worktree without duplicating it at the top level' {
        InModuleScope wtw -Parameters @{ TempDir = $script:tempDir } {
            $script:WtwBackupRoot = Join-Path $TempDir 'backups'
            Mock Test-WtwSourceGitRunning { $false }
            Add-WtwSourceGitRepository -Path '/tmp/demo_auth' -Name '🟢 login' -Hex '#22aa22' -Force
            $after = Get-Content -Path $env:WTW_SOURCEGIT_PREF -Raw | ConvertFrom-Json
            @($after.RepositoryNodes).Count | Should -Be 1
            $after.RepositoryNodes[0].SubNodes[0].Name | Should -Be '🟢 login'
            @(Get-ChildItem -LiteralPath (Join-Path $script:WtwBackupRoot 'sourcegit') -ErrorAction SilentlyContinue).Count |
                Should -BeGreaterOrEqual 1
        }
    }

    It 'removes a nested worktree that a top-level Id scan would miss' {
        InModuleScope wtw -Parameters @{ TempDir = $script:tempDir } {
            $script:WtwBackupRoot = Join-Path $TempDir 'backups'
            Mock Test-WtwSourceGitRunning { $false }
            Remove-WtwSourceGitRepository -Path '/tmp/demo_auth' -Force
            $after = Get-Content -Path $env:WTW_SOURCEGIT_PREF -Raw | ConvertFrom-Json
            @($after.RepositoryNodes).Count | Should -Be 1
            @($after.RepositoryNodes[0].SubNodes).Count | Should -Be 0
        }
    }

    It 'renames the group when the repo emoji changes' {
        InModuleScope wtw -Parameters @{ TempDir = $script:tempDir } {
            $script:WtwBackupRoot = Join-Path $TempDir 'backups'
            Mock Test-WtwSourceGitRunning { $false }
            Mock Get-WtwColors {
                [PSCustomObject]@{ assignments = [PSCustomObject]@{ 'demo/main' = '#111111' } }
            }
            $entry = [PSCustomObject]@{
                mainPath = '/tmp/demo'
                emoji    = '🎸'
            }
            Sync-WtwSourceGitRepoDisplayName -RepoName 'demo' -RepoEntry $entry -Force
            $after = Get-Content -Path $env:WTW_SOURCEGIT_PREF -Raw | ConvertFrom-Json
            $after.RepositoryNodes[0].Name | Should -Be '🎸 demo'
        }
    }
}

Describe 'SourceGit repo folders' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-sg-folder-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
        $script:prefPath = Join-Path $script:tempDir 'preference.json'
        $script:originalPref = $env:WTW_SOURCEGIT_PREF
        $env:WTW_SOURCEGIT_PREF = $script:prefPath
        InModuleScope wtw {
            if (-not (Get-Variable -Name originalRegistryPath -Scope Script -ErrorAction SilentlyContinue)) {
                $script:originalRegistryPath = $script:WtwRegistryPath
            }
        }
    }

    AfterEach {
        $env:WTW_SOURCEGIT_PREF = $script:originalPref
        InModuleScope wtw {
            $script:WtwRegistryPath = $script:originalRegistryPath
            $script:WtwBackupRoot = $null
        }
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'nests a new worktree under an existing repo folder even when the flag is unset' {
        InModuleScope wtw -Parameters @{ TempDir = $script:tempDir; PrefPath = $script:prefPath } {
            $script:originalRegistryPath = $script:WtwRegistryPath
            $script:WtwRegistryPath = Join-Path $TempDir 'registry.json'
            $script:WtwBackupRoot = Join-Path $TempDir 'backups'
            Mock Test-WtwSourceGitRunning { $false }

            [PSCustomObject]@{
                repos = [PSCustomObject]@{
                    demo = [PSCustomObject]@{
                        mainPath  = '/tmp/demo'
                        aliases   = @('dm')
                        worktrees = [PSCustomObject]@{}
                    }
                }
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwRegistryPath -Encoding utf8

            [PSCustomObject]@{
                RepositoryNodes = @(
                    [PSCustomObject]@{
                        Id           = 'wtw-folder:demo'
                        Name         = 'demo'
                        IsRepository = $false
                        SubNodes     = @(
                            [PSCustomObject]@{
                                Id           = '/tmp/demo'
                                Name         = 'demo'
                                IsRepository = $true
                                SubNodes     = @()
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 20 | Set-Content -Path $PrefPath -Encoding utf8

            Add-WtwSourceGitRepository -Path '/tmp/demo_feat' -Name '🟢 feat' -Hex '#22aa22' -RepoName 'demo' -Force
            $after = Get-Content -Path $env:WTW_SOURCEGIT_PREF -Raw | ConvertFrom-Json
            @($after.RepositoryNodes).Count | Should -Be 1
            $after.RepositoryNodes[0].Id | Should -Be 'wtw-folder:demo'
            $childIds = @($after.RepositoryNodes[0].SubNodes | ForEach-Object { $_.Id })
            $childIds | Should -Contain '/tmp/demo_feat'
            $childIds | Should -Contain '/tmp/demo'
        }
    }

    It 'creates a folder and moves main in when sourceGitFolder is true' {
        InModuleScope wtw -Parameters @{ TempDir = $script:tempDir; PrefPath = $script:prefPath } {
            $script:originalRegistryPath = $script:WtwRegistryPath
            $script:WtwRegistryPath = Join-Path $TempDir 'registry.json'
            $script:WtwBackupRoot = Join-Path $TempDir 'backups'
            Mock Test-WtwSourceGitRunning { $false }

            [PSCustomObject]@{
                repos = [PSCustomObject]@{
                    demo = [PSCustomObject]@{
                        mainPath        = '/tmp/demo'
                        aliases         = @('dm')
                        sourceGitFolder = $true
                        worktrees       = [PSCustomObject]@{}
                    }
                }
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwRegistryPath -Encoding utf8

            [PSCustomObject]@{
                RepositoryNodes = @(
                    [PSCustomObject]@{
                        Id           = '/tmp/demo'
                        Name         = 'demo'
                        IsRepository = $true
                        SubNodes     = @()
                    }
                )
            } | ConvertTo-Json -Depth 20 | Set-Content -Path $PrefPath -Encoding utf8

            Add-WtwSourceGitRepository -Path '/tmp/demo_feat' -Name '🟢 feat' -Hex '#22aa22' -RepoName 'demo' -Force
            $after = Get-Content -Path $env:WTW_SOURCEGIT_PREF -Raw | ConvertFrom-Json
            @($after.RepositoryNodes).Count | Should -Be 1
            $after.RepositoryNodes[0].Id | Should -Be 'wtw-folder:demo'
            $childIds = @($after.RepositoryNodes[0].SubNodes | ForEach-Object { $_.Id })
            $childIds | Should -Contain '/tmp/demo'
            $childIds | Should -Contain '/tmp/demo_feat'
        }
    }

    It 'stays at the top level when sourceGitFolder is false and no folder exists' {
        InModuleScope wtw -Parameters @{ TempDir = $script:tempDir; PrefPath = $script:prefPath } {
            $script:originalRegistryPath = $script:WtwRegistryPath
            $script:WtwRegistryPath = Join-Path $TempDir 'registry.json'
            $script:WtwBackupRoot = Join-Path $TempDir 'backups'
            Mock Test-WtwSourceGitRunning { $false }

            [PSCustomObject]@{
                repos = [PSCustomObject]@{
                    demo = [PSCustomObject]@{
                        mainPath        = '/tmp/demo'
                        aliases         = @('dm')
                        sourceGitFolder = $false
                        worktrees       = [PSCustomObject]@{}
                    }
                }
            } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwRegistryPath -Encoding utf8

            [PSCustomObject]@{
                RepositoryNodes = @(
                    [PSCustomObject]@{
                        Id           = '/tmp/demo'
                        Name         = 'demo'
                        IsRepository = $true
                        SubNodes     = @()
                    }
                )
            } | ConvertTo-Json -Depth 20 | Set-Content -Path $PrefPath -Encoding utf8

            Add-WtwSourceGitRepository -Path '/tmp/demo_feat' -Name '🟢 feat' -Hex '#22aa22' -RepoName 'demo' -Force
            $after = Get-Content -Path $env:WTW_SOURCEGIT_PREF -Raw | ConvertFrom-Json
            $ids = @($after.RepositoryNodes | ForEach-Object { $_.Id })
            $ids | Should -Contain '/tmp/demo'
            $ids | Should -Contain '/tmp/demo_feat'
            $ids | Should -Not -Contain 'wtw-folder:demo'
        }
    }
}
