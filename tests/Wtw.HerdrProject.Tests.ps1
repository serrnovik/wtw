BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Open-WtwHerdrProject' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-herdr-" + [guid]::NewGuid())
        $script:projectPath = Join-Path $script:tempDir 'repo_feature'
        New-Item -ItemType Directory -Path $script:projectPath -Force | Out-Null
        $script:fullPath = [System.IO.Path]::GetFullPath($script:projectPath)
        $script:calls = [System.Collections.Generic.List[string]]::new()
        $script:serverUp = $true
        $script:panes = @()
        $script:workspaces = @()

        Mock Get-WtwHerdrExe { '/usr/bin/herdr' }
        Mock Start-WtwHerdrServer { $script:serverUp = $true; $true }
        Mock Invoke-WtwHerdrCommand {
            $script:calls.Add(($ArgumentList -join ' '))
            if (-not $script:serverUp) {
                return [PSCustomObject]@{ ExitCode = 1; Result = $null; ErrorCode = 'server_not_running'; Output = 'no herdr server' }
            }
            $result = switch ("$($ArgumentList[0]) $($ArgumentList[1])") {
                'pane list' { [PSCustomObject]@{ panes = $script:panes } }
                'workspace list' { [PSCustomObject]@{ workspaces = $script:workspaces } }
                'workspace create' { [PSCustomObject]@{ workspace = [PSCustomObject]@{ workspace_id = 'w7' } } }
                default { [PSCustomObject]@{} }
            }
            [PSCustomObject]@{ ExitCode = 0; Result = $result; ErrorCode = $null; Output = '' }
        }
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:tempDir -ErrorAction SilentlyContinue
    }

    It 'creates a labelled workspace at the worktree' {
        $result = Open-WtwHerdrProject -ProjectPath $script:projectPath -PrettyName '🟠 Blue Feature'

        $result.Success | Should -BeTrue
        $result.Created | Should -BeTrue
        $result.Started | Should -BeFalse
        $result.Id | Should -Be 'w7'
        $script:calls | Should -Contain "workspace create --cwd $script:fullPath --label 🟠 Blue Feature --focus"
    }

    It 'relabels and focuses the workspace already rooted at the worktree' {
        $script:panes = @(
            [PSCustomObject]@{ workspace_id = 'w1'; cwd = $script:tempDir },
            [PSCustomObject]@{ workspace_id = 'w2'; cwd = $script:fullPath }
        )

        $result = Open-WtwHerdrProject -ProjectPath $script:projectPath -PrettyName '🟠 Blue Feature'

        $result.Created | Should -BeFalse
        $result.Id | Should -Be 'w2'
        $script:calls | Should -Contain 'workspace rename w2 🟠 Blue Feature'
        $script:calls | Should -Contain 'workspace focus w2'
        @($script:calls | Where-Object { $_ -like 'workspace create*' }).Count | Should -Be 0
    }

    It 'starts herdr in Ghostty when no server is running and labels its first workspace' {
        $script:serverUp = $false
        $script:panes = @([PSCustomObject]@{ workspace_id = 'w1'; cwd = $script:fullPath })

        $result = Open-WtwHerdrProject -ProjectPath $script:projectPath -PrettyName '🟠 Blue Feature'

        Should -Invoke Start-WtwHerdrServer -Times 1
        $result.Success | Should -BeTrue
        $result.Started | Should -BeTrue
        $result.Id | Should -Be 'w1'
        $script:calls | Should -Contain 'workspace rename w1 🟠 Blue Feature'
    }

    It 'reports failure when no server runs and none can be started' {
        $script:serverUp = $false
        Mock Start-WtwHerdrServer { $false }

        $result = Open-WtwHerdrProject -ProjectPath $script:projectPath -PrettyName '🟠 Blue Feature'

        $result.Success | Should -BeFalse
        $result.Reason | Should -Match 'herdr'
    }
}

Describe 'Invoke-WtwHerdrCommand' {
    It 'surfaces the JSON error code herdr prints' -Skip:$IsWindows {
        $script:fakeHerdr = Join-Path ([System.IO.Path]::GetTempPath()) ("fake-herdr-" + [guid]::NewGuid())
        Set-Content -Path $script:fakeHerdr -Value "#!/bin/sh`necho '{""id"":""cli:workspace:list"",""error"":{""code"":""server_not_running"",""message"":""no herdr server""}}'"
        try {
            & chmod +x $script:fakeHerdr
            Mock Get-WtwHerdrExe { $script:fakeHerdr }

            $result = Invoke-WtwHerdrCommand -ArgumentList @('workspace', 'list')

            $result.ErrorCode | Should -Be 'server_not_running'
            $result.ExitCode | Should -Not -Be 0
            $result.Output | Should -Be 'no herdr server'
        } finally {
            Remove-Item -Force $script:fakeHerdr -ErrorAction SilentlyContinue
        }
    }
}
