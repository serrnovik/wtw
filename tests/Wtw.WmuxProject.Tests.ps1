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
        Mock Test-WtwWmuxRunning { $true } -ModuleName wtw
        Mock Get-WtwWmuxShell { $null } -ModuleName wtw
        Mock Invoke-WtwWmuxCommand {
            $script:wmuxCalls.Add(($ArgumentList -join ' '))
            $command = $ArgumentList -join ' '
            if ($command -eq 'list-workspaces') {
                return [PSCustomObject]@{ ExitCode = 0; Output = '{"workspaces":[]}' }
            }
            if ($ArgumentList[0] -eq 'new-workspace') {
                return [PSCustomObject]@{ ExitCode = 0; Output = '{"workspaceId":"ws-123"}' }
            }
            return [PSCustomObject]@{ ExitCode = 0; Output = '{"ok":true}' }
        } -ModuleName wtw
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:tempDir -ErrorAction SilentlyContinue
    }

    It 'creates a wmux workspace rooted at the worktree path' {
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

        $createCall = $script:wmuxCalls | Where-Object { $_ -like 'new-workspace *' } | Select-Object -First 1
        $createCall | Should -Not -BeNullOrEmpty
        $createCall | Should -Match '--title'
        $createCall | Should -Match ([regex]::Escape($script:projectPath))
    } -Skip:(-not $IsWindows)
}

Describe 'Register-WtwWmuxProject' {
    # Register-WtwWmuxProject is a private function; run inside the module scope
    # so mocks of the wmux primitives it calls actually intercept.
    It 'creates the workspace and returns its pretty name' {
        InModuleScope wtw {
            $script:wmuxCalls = [System.Collections.Generic.List[string]]::new()
            Mock Test-WtwWmuxPresent { $true }
            Mock Test-WtwWmuxRunning { $true }
            Mock Get-WtwWmuxShell { $null }
            Mock Invoke-WtwWmuxCommand {
                $script:wmuxCalls.Add(($ArgumentList -join ' '))
                if (($ArgumentList -join ' ') -eq 'list-workspaces') {
                    return [PSCustomObject]@{ ExitCode = 0; Output = '{"workspaces":[]}' }
                }
                if ($ArgumentList[0] -eq 'new-workspace') {
                    return [PSCustomObject]@{ ExitCode = 0; Output = '{"workspaceId":"ws-123"}' }
                }
                return [PSCustomObject]@{ ExitCode = 0; Output = '{"ok":true}' }
            }

            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-wmux-reg-" + [guid]::NewGuid())
            $proj = Join-Path $tmp 'repo_feature'
            New-Item -ItemType Directory -Path $proj -Force | Out-Null
            try {
                $result = Register-WtwWmuxProject -ProjectPath $proj -PrettyName 'Blue Feature' -RepoName 'repo' -TaskName 'feature'
                $result | Should -Be 'Blue Feature'
                ($script:wmuxCalls | Where-Object { $_ -like 'new-workspace *' }).Count | Should -Be 1
            } finally {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
        }
    } -Skip:(-not $IsWindows)

    It 'skips creation when wmux is not running and cannot be started' {
        InModuleScope wtw {
            $script:wmuxCalls = [System.Collections.Generic.List[string]]::new()
            Mock Test-WtwWmuxPresent { $true }
            Mock Test-WtwWmuxRunning { $false }
            Mock Start-WtwWmuxApp { $false }
            Mock Invoke-WtwWmuxCommand {
                $script:wmuxCalls.Add(($ArgumentList -join ' '))
                return [PSCustomObject]@{ ExitCode = 0; Output = '{"workspaces":[]}' }
            }

            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-wmux-reg-" + [guid]::NewGuid())
            $proj = Join-Path $tmp 'repo_feature'
            New-Item -ItemType Directory -Path $proj -Force | Out-Null
            try {
                $result = Register-WtwWmuxProject -ProjectPath $proj -PrettyName 'Blue Feature' -RepoName 'repo' -TaskName 'feature'
                $result | Should -BeNullOrEmpty
                ($script:wmuxCalls | Where-Object { $_ -like 'new-workspace *' }).Count | Should -Be 0
            } finally {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
        }
    } -Skip:(-not $IsWindows)
}
