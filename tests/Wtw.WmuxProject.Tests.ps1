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
        Mock Save-WtwWmuxWorkspaceName { } -ModuleName wtw
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
        @($script:wmuxCalls | Where-Object { $_ -like 'select-workspace *' }).Count | Should -BeGreaterThan 0
        $global:LASTEXITCODE | Should -Be 0
    } -Skip:(-not $IsWindows)

    It 'renames a cwd-matched tab and selects it instead of creating a duplicate' {
        InModuleScope wtw {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-wmux-rename-" + [guid]::NewGuid())
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $full = [System.IO.Path]::GetFullPath($tmp)
            $script:wmuxCalls = [System.Collections.Generic.List[string]]::new()
            try {
                Mock Test-WtwWmuxPresent { $true }
                Mock Test-WtwWmuxRunning { $true }
                Mock Get-WtwWmuxShell { $null }
                Mock Get-WtwWmuxLiveWorkspaces {
                    @(
                        [PSCustomObject]@{ id = 'ws-old'; title = 'NTB-real-dogfood'; cwd = $full }
                    )
                }
                Mock Invoke-WtwWmuxCommand {
                    $script:wmuxCalls.Add(($ArgumentList -join ' '))
                    return [PSCustomObject]@{ ExitCode = 0; Output = '{"ok":true}' }
                }

                $result = Open-WtwWmuxProject -ProjectPath $full -PrettyName '🐕 NTB real dogfood'
                $result.Success | Should -BeTrue
                $result.Created | Should -BeFalse
                $result.Id | Should -Be 'ws-old'
                @($script:wmuxCalls | Where-Object { $_ -like 'new-workspace *' }).Count | Should -Be 0
                $script:wmuxCalls | Should -Contain 'rename-workspace ws-old 🐕 NTB real dogfood'
                $script:wmuxCalls | Should -Contain 'select-workspace ws-old'
            } finally {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
        }
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
                @($script:wmuxCalls | Where-Object { $_ -like 'new-workspace *' }).Count | Should -Be 1
            } finally {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
        }
    } -Skip:(-not $IsWindows)

    It 'skips creation when wmux is not already running without starting it' {
        InModuleScope wtw {
            $script:started = $false
            Mock Test-WtwWmuxPresent { $true }
            Mock Test-WtwWmuxRunning { $false }
            Mock Start-WtwWmuxApp { $script:started = $true; $false }
            Mock Invoke-WtwWmuxCommand {
                return [PSCustomObject]@{ ExitCode = 0; Output = '{"workspaces":[]}' }
            }

            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-wmux-reg-" + [guid]::NewGuid())
            $proj = Join-Path $tmp 'repo_feature'
            New-Item -ItemType Directory -Path $proj -Force | Out-Null
            try {
                $result = Register-WtwWmuxProject -ProjectPath $proj -PrettyName 'Blue Feature' -RepoName 'repo' -TaskName 'feature'
                $result | Should -BeNullOrEmpty
                $script:started | Should -BeFalse
            } finally {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
        }
    } -Skip:(-not $IsWindows)
}

Describe 'Get-WtwWmuxInvoker' {
    It 'runs wmux.js via Electron when standalone node is missing' {
        InModuleScope wtw {
            Mock Get-WtwWmuxCliScript { 'C:\wmux\resources\cli\wmux.js' }
            Mock Get-WtwWmuxNode { $null }
            Mock Get-WtwWmuxExe { 'C:\wmux\wmux.exe' }

            $invoker = Get-WtwWmuxInvoker
            $invoker.Exe | Should -Be 'C:\wmux\wmux.exe'
            $invoker.Prefix | Should -Be @('C:\wmux\resources\cli\wmux.js')
            $invoker.ElectronAsNode | Should -BeTrue
        }
    } -Skip:(-not $IsWindows)

    It 'does not treat a bare wmux.exe on PATH as the CLI' {
        InModuleScope wtw {
            Mock Get-WtwWmuxCliScript { $null }
            Mock Get-Command {
                [PSCustomObject]@{ CommandType = 'Application'; Source = 'C:\wmux\wmux.exe' }
            } -ParameterFilter { $Name -eq 'wmux' }

            $invoker = Get-WtwWmuxInvoker
            $invoker | Should -BeNullOrEmpty
        }
    } -Skip:(-not $IsWindows)
}

Describe 'Find-WtwWmuxWorkspace cwd matching' {
    It 'reuses a workspace by cwd when the title still lacks the repo emoji' {
        InModuleScope wtw {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-wmux-find-" + [guid]::NewGuid())
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $full = [System.IO.Path]::GetFullPath($tmp)
            try {
                Mock Get-WtwWmuxLiveWorkspaces {
                    @(
                        [PSCustomObject]@{ id = 'ws-old'; title = 'snowmain1'; cwd = $full }
                        [PSCustomObject]@{ id = 'ws-emoji'; title = '🎸 snowmain1'; cwd = (Join-Path $full 'other') }
                    )
                }

                $found = Find-WtwWmuxWorkspace -PrettyName '🎸 snowmain1' -ProjectPath $full
                $found.id | Should -Be 'ws-old'
            } finally {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
        }
    }

    It 'falls back to title when no cwd matches' {
        InModuleScope wtw {
            Mock Get-WtwWmuxLiveWorkspaces {
                @(
                    [PSCustomObject]@{ id = 'ws-emoji'; title = '🎸 snowmain1'; cwd = '/somewhere/else' }
                )
            }

            $found = Find-WtwWmuxWorkspace -PrettyName '🎸 snowmain1' -ProjectPath ([System.IO.Path]::GetTempPath())
            $found.id | Should -Be 'ws-emoji'
        }
    }
}

Describe 'ConvertTo-WtwWmuxCliOutput' {
    It 'drops packaged-Electron NODE_OPTIONS noise' {
        InModuleScope wtw {
            $raw = @(
                '[ERROR:electron/shell/common/node_bindings.cc(387)] Most NODE_OPTIONS are not supported in packaged apps.'
                '{"workspaces":[]}'
            )
            ConvertTo-WtwWmuxCliOutput -Raw $raw | Should -Be '{"workspaces":[]}'
        }
    }
}

Describe 'ConvertFrom-WtwWmuxJsonOutput' {
    It 'parses JSON after mixed Electron log lines' {
        InModuleScope wtw {
            $output = @"
[ERROR:electron/shell/common/node_bindings.cc(387)] Most NODE_OPTIONS are not supported in packaged apps.
{"workspaceId":"ws-123"}
"@
            $parsed = ConvertFrom-WtwWmuxJsonOutput -Output $output
            $parsed.workspaceId | Should -Be 'ws-123'
        }
    }
}
