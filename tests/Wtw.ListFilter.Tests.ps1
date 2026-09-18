BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'Select-WtwListItemsByFilter' {
    BeforeAll {
        $script:items = @(
            [PSCustomObject]@{
                Kind = 'repo'; RepoName = 'kulissa-landing'; Repo = 'kulissa-landing'
                TaskName = '-'; Task = '-'; Aliases = "kul`nkulissa-landing"; PrettyName = $null
            }
            [PSCustomObject]@{
                Kind = 'wt'; RepoName = 'kulissa-landing'; Repo = 'kulissa-landing'
                TaskName = 'hero'; Task = 'hero'; Aliases = 'kul-hero'; PrettyName = 'Hero'
            }
            [PSCustomObject]@{
                Kind = 'repo'; RepoName = 'snowmain1'; Repo = 'snowmain1'
                TaskName = '-'; Task = '-'; Aliases = "sn1`nsnowmain1"; PrettyName = $null
            }
            [PSCustomObject]@{
                Kind = 'wt'; RepoName = 'snowmain1'; Repo = 'snowmain1'
                TaskName = 'auth'; Task = 'auth'; Aliases = 'sn1-auth'; PrettyName = 'Auth'
            }
            [PSCustomObject]@{
                Kind = 'wt'; RepoName = 'snowmain1'; Repo = 'snowmain1'
                TaskName = 'kulissa-embed'; Task = 'kulissa-embed'
                Aliases = 'sn1-kulissa-embed'; PrettyName = $null
            }
        )
    }

    It 'keeps a matching repo and every worktree under it' {
        InModuleScope wtw -Parameters @{ Items = $script:items } {
            $hit = @(Select-WtwListItemsByFilter -Items $Items -Filter 'kulissa-land')
            $hit.Kind | Should -Contain 'repo'
            $hit.RepoName | Should -Contain 'kulissa-landing'
            $hit.RepoName | Should -Not -Contain 'snowmain1'
            ($hit | Where-Object { $_.RepoName -eq 'kulissa-landing' -and $_.Kind -eq 'wt' }).TaskName |
                Should -Be 'hero'
        }
    }

    It 'matches the kul prefix the way wtw list -f kul should' {
        InModuleScope wtw -Parameters @{ Items = $script:items } {
            $hit = @(Select-WtwListItemsByFilter -Items $Items -Filter 'kul')
            $hit.RepoName | Should -Contain 'kulissa-landing'
            $hit.TaskName | Should -Contain 'hero'
            $hit.TaskName | Should -Contain 'kulissa-embed'
            $hit.TaskName | Should -Not -Contain 'auth'
            ($hit | Where-Object { $_.RepoName -eq 'snowmain1' -and $_.Kind -eq 'repo' }).Count |
                Should -Be 1
        }
    }

    It 'keeps the parent repo row when only a worktree matches' {
        InModuleScope wtw -Parameters @{ Items = $script:items } {
            $hit = @(Select-WtwListItemsByFilter -Items $Items -Filter 'auth')
            $hit.RepoName | Should -Be @('snowmain1', 'snowmain1')
            $hit.Kind | Should -Be @('repo', 'wt')
            $hit.TaskName | Should -Contain 'auth'
        }
    }

    It 'is case-insensitive' {
        InModuleScope wtw -Parameters @{ Items = $script:items } {
            $hit = @(Select-WtwListItemsByFilter -Items $Items -Filter 'KULISSA')
            $hit.RepoName | Should -Contain 'kulissa-landing'
        }
    }

    It 'returns everything when the needle is blank' {
        InModuleScope wtw -Parameters @{ Items = $script:items } {
            @(Select-WtwListItemsByFilter -Items $Items -Filter ' ').Count |
                Should -Be $Items.Count
        }
    }
}

Describe 'Get-WtwList -Filter' {
    It 'prints a miss instead of an empty table' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "wtw-list-filter-$([guid]::NewGuid())"
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
                Mock Write-WtwHost { }

                Get-WtwList -Filter 'kulissa'
                Should -Invoke Write-WtwHost -Times 1 -ParameterFilter {
                    "$Object" -like "*No repo or worktree matches 'kulissa'*"
                }
            }
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
