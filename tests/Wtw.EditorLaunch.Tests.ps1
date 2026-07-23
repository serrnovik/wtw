BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Test-WtwEditorCli' {
    BeforeAll {
        $script:tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-cli-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:tmp | Out-Null
    }
    AfterAll {
        Remove-Item -Recurse -Force $script:tmp -ErrorAction SilentlyContinue
    }

    It 'returns $false for a command that is not on PATH' {
        Test-WtwEditorCli -Cmd 'wtw-totally-missing-editor-xyz' | Should -BeFalse
    }

    It 'returns $false for a dangling symlink on PATH' {
        $missingTarget = Join-Path $script:tmp 'gone'
        $linkDir = Join-Path $script:tmp 'bin'
        New-Item -ItemType Directory -Path $linkDir | Out-Null
        $link = Join-Path $linkDir 'wtw-dangling-editor'
        New-Item -ItemType SymbolicLink -Path $link -Target $missingTarget | Out-Null
        $oldPath = $env:PATH
        try {
            $env:PATH = "$linkDir$([System.IO.Path]::PathSeparator)$oldPath"
            Test-WtwEditorCli -Cmd 'wtw-dangling-editor' | Should -BeFalse
        } finally {
            $env:PATH = $oldPath
        }
    }

    It 'returns $true for a real executable on PATH' {
        $realDir = Join-Path $script:tmp 'real'
        New-Item -ItemType Directory -Path $realDir | Out-Null
        $exe = Join-Path $realDir 'wtw-real-editor'
        Set-Content -Path $exe -Value "#!/bin/sh`necho hi" -NoNewline
        if (-not $IsWindows) { chmod +x $exe }
        $oldPath = $env:PATH
        try {
            $env:PATH = "$realDir$([System.IO.Path]::PathSeparator)$oldPath"
            Test-WtwEditorCli -Cmd 'wtw-real-editor' | Should -BeTrue
        } finally {
            $env:PATH = $oldPath
        }
    }
}

Describe 'Invoke-WtwEditorCli' {
    BeforeAll {
        # CI agents don't have the Cursor CLI on PATH, and Pester can only
        # mock resolvable commands — stub it when absent (locally the real
        # CLI resolves and no stub is created).
        if (-not (Get-Command cursor -ErrorAction SilentlyContinue)) {
            $script:cursorStubbed = $true
            function global:cursor { }
        }
    }
    AfterAll {
        if ($script:cursorStubbed) {
            Remove-Item function:global:cursor -ErrorAction SilentlyContinue
        }
    }

    It 'opens Cursor workspaces in a new IDE window' {
        $script:cursorArguments = $null
        Mock Test-WtwEditorCli { $true }
        Mock cursor {
            param($first, $second)
            $script:cursorArguments = @($first, $second)
        }

        Invoke-WtwEditorCli -Cmd 'cursor' -Path '/tmp/cursor-worktree.code-workspace'

        $script:cursorArguments | Should -Be @('--new-window', '/tmp/cursor-worktree.code-workspace')
    }

    It 'prefers the renamed antigravity-ide CLI over the legacy antigravity stub' {
        $script:queried = [System.Collections.Generic.List[string]]::new()
        Mock Test-WtwEditorCli { $script:queried.Add($Cmd); $false }
        Mock Test-Path { $false }   # no mac app bundle either

        Invoke-WtwEditorCli -Cmd 'antigravity' -Path '/tmp/x' -ErrorAction SilentlyContinue 2>$null

        $script:queried[0] | Should -Be 'antigravity-ide'
        $script:queried   | Should -Contain 'antigravity'
    }

    It 'errors when no candidate is runnable and no app bundle exists' {
        Mock Test-WtwEditorCli { $false }
        Mock Test-Path { $false }

        { Invoke-WtwEditorCli -Cmd 'antigravity' -Path '/tmp/x' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*not runnable*'
    }
}

Describe 'Open-WtwWorkspace Codex launcher' {
    It 'refreshes Cursor recent workspace metadata before opening the code-workspace file' {
        $worktreeDir = Join-Path $script:tmp 'cursor-worktree'
        New-Item -ItemType Directory -Path $worktreeDir -Force | Out-Null
        $workspaceFile = Join-Path $script:tmp 'cursor-worktree.code-workspace'
        Set-Content -Path $workspaceFile -Value '{}'

        Mock Resolve-WtwTarget {
            [PSCustomObject]@{
                TaskName      = 'cursor-worktree'
                WorktreeEntry = [PSCustomObject]@{
                    path       = $worktreeDir
                    workspace  = $workspaceFile
                    prettyName = 'Blue Cursor Worktree'
                    color      = '#336699'
                }
                RepoEntry     = [PSCustomObject]@{
                    mainPath = $script:tmp
                }
            }
        } -ModuleName wtw
        Mock Register-WtwCursorProject { $WorkspacePath } -ModuleName wtw
        Mock Invoke-WtwEditorCli {} -ModuleName wtw

        Open-WtwWorkspace -Name 'cursor-worktree' -Editor 'cursor'

        Should -Invoke Register-WtwCursorProject -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
            $WorkspacePath -eq $workspaceFile -and
            $ProjectPath -eq $worktreeDir -and
            $PrettyName -eq 'Blue Cursor Worktree' -and
            $Color -eq '#336699'
        }
        Should -Invoke Invoke-WtwEditorCli -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
            $Cmd -eq 'cursor' -and $Path -eq $workspaceFile
        }
    }

    It 'opens Codex with the worktree directory instead of the code-workspace file' {
        $worktreeDir = Join-Path $script:tmp 'codex-worktree'
        New-Item -ItemType Directory -Path $worktreeDir -Force | Out-Null
        $workspaceFile = Join-Path $script:tmp 'codex-worktree.code-workspace'
        Set-Content -Path $workspaceFile -Value '{}'

        Mock Resolve-WtwTarget {
            [PSCustomObject]@{
                WorktreeEntry = [PSCustomObject]@{
                    path       = $worktreeDir
                    workspace  = $workspaceFile
                    prettyName = 'Blue Codex Worktree'
                }
                RepoEntry     = [PSCustomObject]@{
                    mainPath = $script:tmp
                }
            }
        } -ModuleName wtw
        Mock Get-WtwCodexHome { $script:tmp } -ModuleName wtw
        Mock Test-WtwCodexPresent { $true } -ModuleName wtw
        Mock Test-WtwCodexProjectLabel { $false } -ModuleName wtw
        Mock Resolve-WtwCodexStateConflict { @{ proceed = $true; relaunch = $false } } -ModuleName wtw
        Mock Ensure-WtwCodexProjectConfig { $false } -ModuleName wtw
        Mock Set-WtwCodexProjectTrust {} -ModuleName wtw
        Mock Set-WtwCodexProjectLabel { $true } -ModuleName wtw
        Mock Start-WtwCodexApp { $true } -ModuleName wtw
        Mock Invoke-WtwEditorCli { throw 'generic editor path should not be used for Codex' } -ModuleName wtw

        Open-WtwWorkspace -Name 'codex-worktree' -Editor @{ type = 'codex'; appName = 'Codex'; cmd = 'codex' }

        Should -Invoke Start-WtwCodexApp -ModuleName wtw -Times 1 -Exactly -ParameterFilter { $ProjectPath -eq $worktreeDir }
        Should -Invoke Set-WtwCodexProjectLabel -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
            $ProjectPath -eq $worktreeDir -and $PrettyName -eq 'Blue Codex Worktree'
        }
        Should -Invoke Resolve-WtwCodexStateConflict -ModuleName wtw -Times 1 -Exactly
        Should -Invoke Invoke-WtwEditorCli -ModuleName wtw -Times 0
    }

    It 'does not prompt to restart Codex when the sidebar label already matches' {
        $worktreeDir = Join-Path $script:tmp 'codex-labelled-worktree'
        New-Item -ItemType Directory -Path $worktreeDir -Force | Out-Null

        Mock Resolve-WtwTarget {
            [PSCustomObject]@{
                WorktreeEntry = [PSCustomObject]@{
                    path       = $worktreeDir
                    prettyName = 'Existing Codex Label'
                }
                RepoEntry     = [PSCustomObject]@{
                    mainPath = $script:tmp
                }
            }
        } -ModuleName wtw
        Mock Get-WtwCodexHome { $script:tmp } -ModuleName wtw
        Mock Test-WtwCodexPresent { $true } -ModuleName wtw
        Mock Test-WtwCodexProjectLabel { $true } -ModuleName wtw
        Mock Resolve-WtwCodexStateConflict { throw 'already-labelled project should not prompt' } -ModuleName wtw
        Mock Ensure-WtwCodexProjectConfig { $false } -ModuleName wtw
        Mock Set-WtwCodexProjectTrust {} -ModuleName wtw
        Mock Set-WtwCodexProjectLabel { throw 'already-labelled project should not rewrite label' } -ModuleName wtw
        Mock Start-WtwCodexApp { $true } -ModuleName wtw

        Open-WtwWorkspace -Name 'codex-labelled-worktree' -Editor @{ type = 'codex'; appName = 'Codex'; cmd = 'codex' }

        Should -Invoke Resolve-WtwCodexStateConflict -ModuleName wtw -Times 0
        Should -Invoke Set-WtwCodexProjectLabel -ModuleName wtw -Times 0
        Should -Invoke Start-WtwCodexApp -ModuleName wtw -Times 1 -Exactly -ParameterFilter { $ProjectPath -eq $worktreeDir }
    }

    It 'skips the restart prompt when requested' {
        $worktreeDir = Join-Path $script:tmp 'codex-skip-restart-worktree'
        New-Item -ItemType Directory -Path $worktreeDir -Force | Out-Null

        Mock Resolve-WtwTarget {
            [PSCustomObject]@{
                WorktreeEntry = [PSCustomObject]@{
                    path       = $worktreeDir
                    prettyName = 'Needs Restart'
                }
                RepoEntry     = [PSCustomObject]@{
                    mainPath = $script:tmp
                }
            }
        } -ModuleName wtw
        Mock Get-WtwCodexHome { $script:tmp } -ModuleName wtw
        Mock Test-WtwCodexPresent { $true } -ModuleName wtw
        Mock Test-WtwCodexProjectLabel { $false } -ModuleName wtw
        Mock Test-WtwCodexAppRunning { $true } -ModuleName wtw
        Mock Resolve-WtwCodexStateConflict { throw '--skip-restart should not prompt' } -ModuleName wtw
        Mock Ensure-WtwCodexProjectConfig { $false } -ModuleName wtw
        Mock Set-WtwCodexProjectTrust {} -ModuleName wtw
        Mock Set-WtwCodexProjectLabel { throw '--skip-restart should not rewrite label while Codex is running' } -ModuleName wtw
        Mock Start-WtwCodexApp { $true } -ModuleName wtw

        Open-WtwWorkspace -Name 'codex-skip-restart-worktree' -Editor @{ type = 'codex'; appName = 'Codex'; cmd = 'codex' } -SkipRestart

        Should -Invoke Resolve-WtwCodexStateConflict -ModuleName wtw -Times 0
        Should -Invoke Set-WtwCodexProjectLabel -ModuleName wtw -Times 0
        Should -Invoke Start-WtwCodexApp -ModuleName wtw -Times 1 -Exactly -ParameterFilter { $ProjectPath -eq $worktreeDir }
    }
}
