BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'wtw list git fallback' {
    It 'lists registered repos without throwing when git is unavailable' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "wtw-list-git-$([guid]::NewGuid())"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        try {
            InModuleScope wtw -Parameters @{ TempDir = $tempDir } {
                $script:WtwRegistryPath = Join-Path $TempDir 'registry.json'
                $script:WtwConfigPath = Join-Path $TempDir 'config.json'
                $script:WtwColorsPath = Join-Path $TempDir 'colors.json'

                [PSCustomObject]@{
                    repos = [PSCustomObject]@{
                        demo = [PSCustomObject]@{
                            mainPath          = $TempDir
                            templateWorkspace = $null
                            aliases           = @('d')
                            worktrees         = [PSCustomObject]@{}
                        }
                    }
                } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwRegistryPath -Encoding utf8

                Mock Get-WtwGitCommand { $null }

                { Get-WtwList } | Should -Not -Throw
            }
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'lists legacy worktrees without optional display metadata' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "wtw-list-legacy-$([guid]::NewGuid())"
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        try {
            InModuleScope wtw -Parameters @{ TempDir = $tempDir } {
                $script:WtwRegistryPath = Join-Path $TempDir 'registry.json'
                $script:WtwConfigPath = Join-Path $TempDir 'config.json'
                $script:WtwColorsPath = Join-Path $TempDir 'colors.json'

                [PSCustomObject]@{
                    repos = [PSCustomObject]@{
                        demo = [PSCustomObject]@{
                            mainPath          = $TempDir
                            templateWorkspace = $null
                            aliases           = @('d')
                            worktrees         = [PSCustomObject]@{
                                legacy = [PSCustomObject]@{
                                    path      = $TempDir
                                    branch    = 'legacy'
                                    workspace = $null
                                    created   = '2026-01-01'
                                    color     = '#123456'
                                }
                            }
                        }
                    }
                } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwRegistryPath -Encoding utf8

                Mock Get-WtwGitCommand { $null }

                { Get-WtwList -ErrorAction Stop } | Should -Not -Throw
            }
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Test-WtwWorktreeDirty' {
    BeforeAll {
        $script:repo = Join-Path ([System.IO.Path]::GetTempPath()) "wtw-dirty-$([guid]::NewGuid())"
        New-Item -Path $script:repo -ItemType Directory -Force | Out-Null
        git -C $script:repo init -q
        git -C $script:repo config user.email 'test@example.com'
        git -C $script:repo config user.name 'test'
        git -C $script:repo config core.autocrlf false
        # Committed before the eol rule, like the repo's legacy CRLF files.
        [IO.File]::WriteAllText((Join-Path $script:repo 'legacy.yml'), "a: 1`r`nb: 2`r`n")
        [IO.File]::WriteAllText((Join-Path $script:repo 'plain.txt'), "one`n")
        git -C $script:repo add -A
        git -C $script:repo commit -qm init
        [IO.File]::WriteAllText((Join-Path $script:repo '.gitattributes'), "*.yml text eol=lf`n")
        git -C $script:repo add .gitattributes
        git -C $script:repo commit -qm eol
    }
    AfterAll {
        Remove-Item -Path $script:repo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'treats line-ending-only differences as clean' {
        # Touching the file makes git re-check it and report it as modified.
        (Get-Item (Join-Path $script:repo 'legacy.yml')).LastWriteTime = (Get-Date).AddMinutes(1)
        git -C $script:repo status --porcelain | Should -Not -BeNullOrEmpty
        InModuleScope wtw -Parameters @{ Repo = $script:repo } {
            Test-WtwWorktreeDirty -Path $Repo | Should -BeFalse
        }
    }

    It 'reports content changes and untracked files as dirty' {
        InModuleScope wtw -Parameters @{ Repo = $script:repo } {
            [IO.File]::WriteAllText((Join-Path $Repo 'new.txt'), 'x')
            Test-WtwWorktreeDirty -Path $Repo | Should -BeTrue
            Remove-Item (Join-Path $Repo 'new.txt')
            [IO.File]::WriteAllText((Join-Path $Repo 'plain.txt'), "two`n")
            Test-WtwWorktreeDirty -Path $Repo | Should -BeTrue
            git -C $Repo checkout -q -- plain.txt
        }
    }
}
