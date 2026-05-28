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
}
