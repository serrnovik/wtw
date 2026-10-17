BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Open-WtwWorkmuxProject' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-workmux-" + [guid]::NewGuid())
        $script:projectPath = Join-Path $script:tempDir 'repo_feature'
        New-Item -ItemType Directory -Path $script:projectPath -Force | Out-Null
        $script:calls = [System.Collections.Generic.List[string]]::new()
        $script:openOutput = "✓ Opened tmux window for 'repo_feature'"

        Mock Get-WtwWorkmuxExe { '/usr/bin/workmux' }
        Mock Test-WtwTmuxServer { $true }
        Mock Start-WtwTmuxServer { $true }
        Mock Invoke-WtwWorkmuxCommand {
            $script:calls.Add("$WorkingDirectory :: $($ArgumentList -join ' ')")
            [PSCustomObject]@{ ExitCode = 0; Output = $script:openOutput }
        }
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:tempDir -ErrorAction SilentlyContinue
    }

    It 'opens the worktree by directory name from inside it' {
        $result = Open-WtwWorkmuxProject -ProjectPath $script:projectPath

        $full = [System.IO.Path]::GetFullPath($script:projectPath)
        $result.Success | Should -BeTrue
        $result.Created | Should -BeTrue
        $result.Name | Should -Be 'repo_feature'
        $script:calls | Should -Contain "$full :: open repo_feature"
        Should -Invoke Start-WtwTmuxServer -Times 0
    }

    It 'reports a switch to an existing window' {
        $script:openOutput = "✓ Switched to existing tmux window for 'repo_feature'"

        $result = Open-WtwWorkmuxProject -ProjectPath $script:projectPath

        $result.Success | Should -BeTrue
        $result.Created | Should -BeFalse
    }

    It 'starts tmux in Ghostty when no server is running' {
        Mock Test-WtwTmuxServer { $false }

        $result = Open-WtwWorkmuxProject -ProjectPath $script:projectPath

        Should -Invoke Start-WtwTmuxServer -Times 1
        $result.Started | Should -BeTrue
        $result.Success | Should -BeTrue
    }

    It 'fails without calling workmux when tmux cannot be started' {
        Mock Test-WtwTmuxServer { $false }
        Mock Start-WtwTmuxServer { $false }

        $result = Open-WtwWorkmuxProject -ProjectPath $script:projectPath

        $result.Success | Should -BeFalse
        $result.Reason | Should -Match 'tmux'
        $script:calls.Count | Should -Be 0
    }

    It 'passes workmux errors through' {
        Mock Invoke-WtwWorkmuxCommand { [PSCustomObject]@{ ExitCode = 1; Output = 'worktree not found' } }

        $result = Open-WtwWorkmuxProject -ProjectPath $script:projectPath

        $result.Success | Should -BeFalse
        $result.Reason | Should -Be 'worktree not found'
    }
}
