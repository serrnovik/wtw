BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Open-WtwWmuxWorkspace' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-wmux-open-" + [guid]::NewGuid())
        $script:projectPath = Join-Path $script:tempDir 'repo_feature'
        New-Item -ItemType Directory -Path $script:projectPath -Force | Out-Null
        $script:wmuxCalls = [System.Collections.Generic.List[string]]::new()

        Mock Test-WtwWmuxPresent { $true } -ModuleName wtw
        Mock Invoke-WtwWmuxCommand {
            $script:wmuxCalls.Add(($ArgumentList -join ' '))
            $command = $ArgumentList -join ' '
            if ($command -eq 'list-workspaces --json') {
                return [PSCustomObject]@{ ExitCode = 0; Output = '[]' }
            }
            if ($command -eq 'list-surfaces --json') {
                return [PSCustomObject]@{ ExitCode = 0; Output = '[]' }
            }
            return [PSCustomObject]@{ ExitCode = 0; Output = '' }
        } -ModuleName wtw
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:tempDir -ErrorAction SilentlyContinue
    }

    It 'reports wmux integration as pending without invoking workspace commands' {
        $target = [PSCustomObject]@{
            RepoName      = 'repo'
            TaskName      = 'feature'
            WorktreeEntry = [PSCustomObject]@{
                path       = $script:projectPath
                prettyName = 'Blue Feature'
                color      = '#336699'
            }
            RepoEntry     = [PSCustomObject]@{ mainPath = $script:tempDir }
        }

        Open-WtwWmuxWorkspace -Target $target

        $script:wmuxCalls.Count | Should -Be 0
    } -Skip:(-not $IsWindows)

    It 'does not register a worktree while wmux substrate support is pending' {
        Mock Get-WtwColors {
            [PSCustomObject]@{
                palette     = @()
                assignments = [PSCustomObject]@{
                    'repo/main' = '#228833'
                }
            }
        } -ModuleName wtw

        $result = Register-WtwWmuxProject -ProjectPath $script:projectPath -PrettyName 'Blue Feature' -RepoName 'repo' -TaskName 'feature'

        $result | Should -BeNullOrEmpty
        $script:wmuxCalls.Count | Should -Be 0
    } -Skip:(-not $IsWindows)
}
