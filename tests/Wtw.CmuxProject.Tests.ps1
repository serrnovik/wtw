BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
    $script:originalBackupRoot = $env:WTW_BACKUP_ROOT
    $env:WTW_BACKUP_ROOT = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-bak-cmux-" + [guid]::NewGuid())

    function script:Get-WtwExpectedWorktreeTitle {
        param(
            [Parameter(Mandatory)][string]$PrettyName,
            [string]$TaskName,
            [string]$RepoEmoji
        )
        InModuleScope wtw -Parameters @{
            PrettyName = $PrettyName
            TaskName   = $TaskName
            RepoEmoji  = $RepoEmoji
        } {
            $repo = if ($RepoEmoji) { [PSCustomObject]@{ emoji = $RepoEmoji } } else { $null }
            Format-WtwWorktreeDisplayName -Name $PrettyName -TaskName $TaskName -RepoEntry $repo
        }
    }
}

AfterAll {
    if ($env:WTW_BACKUP_ROOT -and (Test-Path $env:WTW_BACKUP_ROOT)) {
        Remove-Item -Recurse -Force $env:WTW_BACKUP_ROOT -ErrorAction SilentlyContinue
    }
    $env:WTW_BACKUP_ROOT = $script:originalBackupRoot
}

Describe 'cmux project registration' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-cmux-" + [guid]::NewGuid())
        $script:projectPath = Join-Path $script:tempDir 'repo_feature'
        $script:configPath = Join-Path $script:tempDir 'cmux.json'
        New-Item -ItemType Directory -Path $script:projectPath -Force | Out-Null

        Mock Test-WtwCmuxPresent { $true }
        Mock Invoke-WtwCmuxCommand { [PSCustomObject]@{ ExitCode = 0; Output = '' } }
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:tempDir -ErrorAction SilentlyContinue
    }

    It 'adds an idempotent workspace command entry' {
        $key1 = Register-WtwCmuxProject `
            -ProjectPath $script:projectPath `
            -PrettyName 'Blue Feature' `
            -Color '#336699' `
            -RepoName 'repo' `
            -TaskName 'feature' `
            -ConfigPath $script:configPath

        $key2 = Register-WtwCmuxProject `
            -ProjectPath $script:projectPath `
            -PrettyName 'Blue Feature' `
            -Color '#336699' `
            -RepoName 'repo' `
            -TaskName 'feature' `
            -ConfigPath $script:configPath

        $key1 | Should -Be $key2
        $config = Get-Content -Path $script:configPath -Raw | ConvertFrom-Json
        @($config.commands).Count | Should -Be 1
        $config.commands[0].id | Should -Be $key1
        $config.commands[0].name | Should -Be 'wtw: Blue Feature'
        $config.commands[0].workspace.cwd | Should -Be $script:projectPath
        $config.commands[0].workspace.color | Should -Be '#336699'
        $config.commands[0].workspace.restart | Should -Be 'ignore'
        $config.commands[0].workspace.layout.pane.surfaces[0].name | Should -Be '🖥️🌳 Blue Feature'
        $config.commands[0].workspace.layout.pane.surfaces[0].command | Should -Be 'pwsh -NoLogo -NoExit -Command "Clear-Host; wtw __cmux_init_current"'
        $config.workspaceGroups.byCwd.PSObject.Properties[$script:projectPath].Value.color | Should -Be '#336699'

        Should -Invoke Invoke-WtwCmuxCommand -Times 0 -Exactly
    }

    It 'preserves unrelated commands and removes the wtw entry' {
        $existing = [PSCustomObject]@{
            schemaVersion = 1
            commands      = @(
                [PSCustomObject]@{
                    name    = 'Run Tests'
                    command = 'npm test'
                }
            )
        }
        $existing | ConvertTo-Json -Depth 10 | Set-Content -Path $script:configPath -Encoding utf8

        $key = Register-WtwCmuxProject `
            -ProjectPath $script:projectPath `
            -PrettyName 'Green Feature' `
            -Color '#228833' `
            -ConfigPath $script:configPath

        Unregister-WtwCmuxProject -ProjectPath $script:projectPath -CommandKey $key -ConfigPath $script:configPath

        $config = Get-Content -Path $script:configPath -Raw | ConvertFrom-Json
        @($config.commands).Count | Should -Be 1
        $config.commands[0].name | Should -Be 'Run Tests'
    }
}

Describe 'cmux workspace output parsing' {
    It 'parses ref-first list-workspaces output' {
        $parsed = ConvertFrom-WtwCmuxWorkspaceListOutput @'
* workspace:1 Main [selected]
workspace:2 Blue Feature
workspace:3
'@

        @($parsed).Count | Should -Be 3
        $parsed[0].ref | Should -Be 'workspace:1'
        $parsed[0].name | Should -Be 'Main'
        $parsed[1].ref | Should -Be 'workspace:2'
        $parsed[1].name | Should -Be 'Blue Feature'
        $parsed[2].ref | Should -Be 'workspace:3'
    }

    It 'parses current-workspace text output' {
        $parsed = ConvertFrom-WtwCmuxCurrentWorkspaceOutput 'workspace:4'

        $parsed.ref | Should -Be 'workspace:4'
    }
}

Describe 'Open-WtwCmuxWorkspace' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-cmux-open-" + [guid]::NewGuid())
        $script:projectPath = Join-Path $script:tempDir 'repo_feature'
        New-Item -ItemType Directory -Path $script:projectPath -Force | Out-Null
        $script:cmuxCalls = [System.Collections.Generic.List[string]]::new()

        Mock Test-WtwCmuxPresent { $true } -ModuleName wtw
        Mock Open-WtwCmuxAppPath { $true } -ModuleName wtw
        Mock Open-WtwCmuxAppleScriptWorkspace { $false } -ModuleName wtw
        Mock Register-WtwCmuxProject { 'wtw.test' } -ModuleName wtw
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:tempDir -ErrorAction SilentlyContinue
    }

    It 'selects an existing cmux workspace by cwd' {
        Mock Invoke-WtwCmuxCommand {
            $script:cmuxCalls.Add(($ArgumentList -join ' '))
            $command = $ArgumentList -join ' '
            if ($command -eq 'list-workspaces --json') {
                return [PSCustomObject]@{
                    ExitCode = 0
                    Output   = @"
{
  "workspaces": [
    {
      "ref": "workspace:2",
      "title": "Path Named Workspace",
      "current_directory": "$($script:projectPath.Replace('\', '\\'))"
    }
  ]
}
"@
                }
            }
            return [PSCustomObject]@{ ExitCode = 0; Output = '' }
        } -ModuleName wtw

        $target = [PSCustomObject]@{
            RepoName       = 'repo'
            TaskName       = 'feature'
            WorktreeEntry  = [PSCustomObject]@{
                path       = $script:projectPath
                prettyName = 'Blue Feature'
                color      = '#336699'
            }
            RepoEntry      = [PSCustomObject]@{ mainPath = $script:tempDir }
        }

        Open-WtwCmuxWorkspace -Target $target

        $expectedTitle = Get-WtwExpectedWorktreeTitle -PrettyName 'Blue Feature' -TaskName 'feature'
        $script:cmuxCalls | Should -Contain 'select-workspace --workspace workspace:2'
        ($script:cmuxCalls | Where-Object { $_ -like 'new-workspace*' }).Count | Should -Be 0
        $script:cmuxCalls | Should -Contain "workspace-action --workspace workspace:2 --action rename --title $expectedTitle"
        $script:cmuxCalls | Should -Contain 'workspace-action --workspace workspace:2 --action set-color --color #336699'
        $script:cmuxCalls | Should -Contain 'set-status wtw repo/feature --workspace workspace:2 --icon git-branch --color #336699 --priority 90'
    }

    It 'uses the default status color when the target color is empty' {
        Mock Invoke-WtwCmuxCommand {
            $script:cmuxCalls.Add(($ArgumentList -join ' '))
            $command = $ArgumentList -join ' '
            if ($command -eq 'list-workspaces --json') {
                return [PSCustomObject]@{
                    ExitCode = 0
                    Output   = @"
{
  "workspaces": [
    {
      "ref": "workspace:2",
      "title": "Uncoloured Feature",
      "current_directory": "$($script:projectPath.Replace('\', '\\'))"
    }
  ]
}
"@
                }
            }
            return [PSCustomObject]@{ ExitCode = 0; Output = '' }
        } -ModuleName wtw

        $target = [PSCustomObject]@{
            RepoName       = 'repo'
            TaskName       = 'uncoloured'
            WorktreeEntry  = [PSCustomObject]@{
                path       = $script:projectPath
                prettyName = 'Uncoloured Feature'
                color      = ''
            }
            RepoEntry      = [PSCustomObject]@{ mainPath = $script:tempDir }
        }

        { Open-WtwCmuxWorkspace -Target $target } | Should -Not -Throw

        $script:cmuxCalls | Should -Contain 'set-status wtw repo/uncoloured --workspace workspace:2 --icon git-branch --color #7A4FD8 --priority 90'
    }

    It 'creates a named cwd workspace when none is already open' {
        Mock Invoke-WtwCmuxCommand {
            $script:cmuxCalls.Add(($ArgumentList -join ' '))
            $command = $ArgumentList -join ' '
            if ($command -eq 'list-workspaces --json') {
                return [PSCustomObject]@{ ExitCode = 0; Output = '' }
            }
            if ($command -eq 'current-workspace') {
                return [PSCustomObject]@{ ExitCode = 0; Output = 'workspace:4' }
            }
            return [PSCustomObject]@{ ExitCode = 0; Output = '' }
        } -ModuleName wtw

        $target = [PSCustomObject]@{
            RepoName       = 'repo'
            TaskName       = 'green'
            WorktreeEntry  = [PSCustomObject]@{
                path       = $script:projectPath
                prettyName = 'Green Feature'
                color      = '#228833'
            }
            RepoEntry      = [PSCustomObject]@{ mainPath = $script:tempDir }
        }

        Open-WtwCmuxWorkspace -Target $target

        $expectedTitle = Get-WtwExpectedWorktreeTitle -PrettyName 'Green Feature' -TaskName 'green'
        $script:cmuxCalls | Should -Contain "new-workspace --name $expectedTitle --cwd $script:projectPath --command pwsh -NoLogo -NoExit -Command `"Clear-Host; wtw __cmux_init_current`" --focus true --description wtw: repo/green"
        ($script:cmuxCalls | Where-Object { $_ -eq "workspace-action --workspace workspace:4 --action rename --title $expectedTitle" }).Count | Should -Be 0
        $script:cmuxCalls | Should -Contain 'workspace-action --workspace workspace:4 --action set-color --color #228833'
    }

    It 'titles a main checkout with the repo emoji, not the first alias' {
        Mock Get-WtwColors {
            [PSCustomObject]@{ assignments = [PSCustomObject]@{} }
        } -ModuleName wtw
        Mock Invoke-WtwCmuxCommand {
            $script:cmuxCalls.Add(($ArgumentList -join ' '))
            $command = $ArgumentList -join ' '
            if ($command -eq 'list-workspaces --json') {
                return [PSCustomObject]@{ ExitCode = 0; Output = '' }
            }
            if ($command -eq 'current-workspace') {
                return [PSCustomObject]@{ ExitCode = 0; Output = 'workspace:5' }
            }
            return [PSCustomObject]@{ ExitCode = 0; Output = '' }
        } -ModuleName wtw

        $target = [PSCustomObject]@{
            RepoName      = 'snowmain1'
            TaskName      = $null
            WorktreeEntry = $null
            RepoEntry     = [PSCustomObject]@{
                mainPath = $script:projectPath
                aliases  = @('sn1')
                emoji    = '🎸'
            }
        }

        Open-WtwCmuxWorkspace -Target $target

        $create = $script:cmuxCalls | Where-Object { $_ -like 'new-workspace *' } | Select-Object -First 1
        $create | Should -Match '--name 🎸 snowmain1'
        $create | Should -Not -Match '--name sn1'
        $create | Should -Match ([regex]::Escape("--cwd $script:projectPath"))
        $create | Should -Match '--description wtw: snowmain1'
    }

    It 'uses AppleScript fallback when socket workspace creation is denied' {
        Mock Invoke-WtwCmuxCommand {
            $script:cmuxCalls.Add(($ArgumentList -join ' '))
            $command = $ArgumentList -join ' '
            if ($command -eq 'list-workspaces --json') {
                return [PSCustomObject]@{ ExitCode = 1; Output = 'Error: ERROR: Access denied - only processes started inside cmux can connect' }
            }
            if ($command -like 'new-workspace*') {
                return [PSCustomObject]@{ ExitCode = 1; Output = 'Error: ERROR: Access denied - only processes started inside cmux can connect' }
            }
            return [PSCustomObject]@{ ExitCode = 0; Output = '' }
        } -ModuleName wtw
        Mock Open-WtwCmuxAppleScriptWorkspace { $true } -ModuleName wtw

        $target = [PSCustomObject]@{
            RepoName       = 'repo'
            TaskName       = 'denied'
            WorktreeEntry  = [PSCustomObject]@{
                path       = $script:projectPath
                prettyName = 'Denied Feature'
                color      = '#8844aa'
            }
            RepoEntry      = [PSCustomObject]@{ mainPath = $script:tempDir }
        }

        Open-WtwCmuxWorkspace -Target $target

        $expectedTitle = Get-WtwExpectedWorktreeTitle -PrettyName 'Denied Feature' -TaskName 'denied'
        Should -Invoke Open-WtwCmuxAppleScriptWorkspace -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
            $ProjectPath -eq $script:projectPath -and
            $PrettyName -eq $expectedTitle -and
            $InitCommand -match '^clear; cd ' -and
            $InitCommand -notmatch 'wtw ' -and
            $InitCommand -notmatch 'Set-Location' -and
            $InitCommand -notmatch 'Clear-Host'
        }
        Should -Invoke Open-WtwCmuxAppPath -ModuleName wtw -Times 0 -Exactly
        $script:cmuxCalls | Should -Contain "new-workspace --name $expectedTitle --cwd $script:projectPath --command pwsh -NoLogo -NoExit -Command `"Clear-Host; wtw __cmux_init_current`" --focus true --description wtw: repo/denied"
        ($script:cmuxCalls | Where-Object { $_ -eq $script:projectPath }).Count | Should -Be 0
    }

    It 'falls back to macOS app open when AppleScript fallback fails' {
        Mock Invoke-WtwCmuxCommand {
            $script:cmuxCalls.Add(($ArgumentList -join ' '))
            $command = $ArgumentList -join ' '
            if ($command -eq 'list-workspaces --json') {
                return [PSCustomObject]@{ ExitCode = 1; Output = 'Error: connection refused' }
            }
            if ($command -like 'new-workspace*') {
                return [PSCustomObject]@{ ExitCode = 1; Output = 'Error: connection refused' }
            }
            return [PSCustomObject]@{ ExitCode = 0; Output = '' }
        } -ModuleName wtw

        $target = [PSCustomObject]@{
            RepoName       = 'repo'
            TaskName       = 'offline'
            WorktreeEntry  = [PSCustomObject]@{
                path       = $script:projectPath
                prettyName = 'Offline Feature'
                color      = '#8844aa'
            }
            RepoEntry      = [PSCustomObject]@{ mainPath = $script:tempDir }
        }

        Open-WtwCmuxWorkspace -Target $target

        Should -Invoke Open-WtwCmuxAppPath -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
            $ProjectPath -eq $script:projectPath
        }
    }
}

Describe 'cmux shell startup metadata hook' {
    It 'applies pretty name and color to the current cmux workspace' {
        $oldWorkspaceId = $env:CMUX_WORKSPACE_ID
        $oldSurfaceId = $env:CMUX_SURFACE_ID
        try {
            $env:CMUX_WORKSPACE_ID = 'workspace:9'
            $env:CMUX_SURFACE_ID = 'surface:9'
            Mock Resolve-WtwCurrentTarget { 'feature' } -ModuleName wtw
            Mock Resolve-WtwTarget {
                [PSCustomObject]@{
                    RepoName      = 'repo'
                    TaskName      = 'feature'
                    WorktreeEntry = [PSCustomObject]@{
                        path       = $TestDrive
                        prettyName = '🟢 Feature'
                        color      = '#96dd2c'
                    }
                    RepoEntry     = [PSCustomObject]@{ mainPath = $TestDrive }
                }
            } -ModuleName wtw
            Mock Get-WtwCmuxBin { 'cmux' } -ModuleName wtw
            Mock Invoke-WtwCmuxRawCommand { [PSCustomObject]@{ ExitCode = 0; Output = '' } } -ModuleName wtw

            $expectedTitle = Get-WtwExpectedWorktreeTitle -PrettyName '🟢 Feature' -TaskName 'feature'
            $expectedTab = "🖥️🌳 $expectedTitle"

            Invoke-Wtw __cmux_apply_current

            Should -Invoke Invoke-WtwCmuxRawCommand -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -eq "workspace-action --workspace workspace:9 --action rename --title $expectedTitle"
            }
            Should -Invoke Invoke-WtwCmuxRawCommand -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -eq 'workspace-action --workspace workspace:9 --action set-color --color #96dd2c'
            }
            Should -Invoke Invoke-WtwCmuxRawCommand -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -eq 'set-status wtw repo/feature --workspace workspace:9 --icon git-branch --color #96dd2c --priority 90'
            }
            Should -Invoke Invoke-WtwCmuxRawCommand -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -eq "rename-tab --workspace workspace:9 --surface surface:9 $expectedTab"
            }
        } finally {
            $env:CMUX_WORKSPACE_ID = $oldWorkspaceId
            $env:CMUX_SURFACE_ID = $oldSurfaceId
        }
    }

    It 'runs normal terminal session setup for PowerShell cmux startup' {
        $oldWorkspaceId = $env:CMUX_WORKSPACE_ID
        $oldSurfaceId = $env:CMUX_SURFACE_ID
        try {
            $env:CMUX_WORKSPACE_ID = 'workspace:10'
            $env:CMUX_SURFACE_ID = 'surface:10'
            Mock Resolve-WtwCurrentTarget { 'feature' } -ModuleName wtw
            Mock Resolve-WtwTarget {
                [PSCustomObject]@{
                    RepoName      = 'repo'
                    TaskName      = 'feature'
                    WorktreeEntry = [PSCustomObject]@{
                        path       = $TestDrive
                        prettyName = '🟢 Feature'
                        color      = '#96dd2c'
                    }
                    RepoEntry     = [PSCustomObject]@{ mainPath = $TestDrive }
                }
            } -ModuleName wtw
            Mock Enter-WtwWorktree {} -ModuleName wtw
            Mock Get-WtwCmuxBin { 'cmux' } -ModuleName wtw
            Mock Invoke-WtwCmuxRawCommand { [PSCustomObject]@{ ExitCode = 0; Output = '' } } -ModuleName wtw

            $expectedTitle = Get-WtwExpectedWorktreeTitle -PrettyName '🟢 Feature' -TaskName 'feature'
            $expectedTab = "🖥️🌳 $expectedTitle"

            Invoke-Wtw __cmux_init_current

            Should -Invoke Enter-WtwWorktree -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'feature'
            }
            Should -Invoke Invoke-WtwCmuxRawCommand -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -eq "workspace-action --workspace workspace:10 --action rename --title $expectedTitle"
            }
            Should -Invoke Invoke-WtwCmuxRawCommand -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -eq 'workspace-action --workspace workspace:10 --action set-color --color #96dd2c'
            }
            Should -Invoke Invoke-WtwCmuxRawCommand -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -eq 'set-status wtw repo/feature --workspace workspace:10 --icon git-branch --color #96dd2c --priority 90'
            }
            Should -Invoke Invoke-WtwCmuxRawCommand -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -eq "rename-tab --workspace workspace:10 --surface surface:10 $expectedTab"
            }
        } finally {
            $env:CMUX_WORKSPACE_ID = $oldWorkspaceId
            $env:CMUX_SURFACE_ID = $oldSurfaceId
        }
    }
}

Describe 'cmux AppleScript POSIX init' {
    It 'cds with POSIX quoting and does not type PowerShell or wtw hooks' {
        InModuleScope wtw {
            $cmd = Get-WtwCmuxLocalAppleScriptInitCommand -ProjectPath $TestDrive
            $quoted = ConvertTo-WtwPosixSingleQuotedLiteral -Value ([System.IO.Path]::GetFullPath($TestDrive))
            $cmd | Should -Be "clear; cd $quoted"
            $cmd | Should -Not -Match 'Set-Location'
            $cmd | Should -Not -Match 'Clear-Host'
            $cmd | Should -Not -Match 'wtw'
            $cmd | Should -Not -Match '__cmux_'
        }
    }

    It 'searches every cmux window and opens a new window on a miss' {
        InModuleScope wtw {
            $source = Get-WtwCmuxAppleScriptFallbackSource
            $source | Should -Match 'repeat with candidateWindow in windows'
            $source | Should -Match 'set createdWindow to new window'
            $source | Should -Not -Match 'new tab in'
            $source | Should -Not -Match 'front window'
        }
    }

    It 'escapes single quotes in the path for POSIX shells' {
        InModuleScope wtw {
            ConvertTo-WtwPosixSingleQuotedLiteral -Value "it's" | Should -Be "'it'\''s'"
        }
    }
}

Describe 'cmux remote SSH workspace' {
    BeforeEach {
        $script:cmuxCalls = [System.Collections.Generic.List[string]]::new()
        $script:remoteHost = @{
            Name      = 'workstation'
            Aliases   = @('at')
            Emoji     = '🧊'
            Label     = 'AT'
            User      = 'dev'
            HostName  = 'workstation.local'
            HostNames = @('workstation.local')
        }
    }

    It 'builds a go command that keeps the typed host and optional via' {
        Get-WtwCmuxRemoteGoInnerCommand -HostSelector 'at' | Should -Be 'wtw --on at go'
        Get-WtwCmuxRemoteGoInnerCommand -HostSelector 'at' -Name 'auth' |
            Should -Be 'wtw --on at go auth'
        Get-WtwCmuxRemoteGoInnerCommand -HostSelector 'at' -Name 'auth' -Via 'tailscale' |
            Should -Be 'wtw --on at --via tailscale go auth'
        Get-WtwCmuxRemoteGoInnerCommand -HostSelector 'at' -Name 'onboarding video' |
            Should -Be "wtw --on at go 'onboarding video'"
        Get-WtwCmuxRemoteGoCommand -HostSelector 'at' -Name 'auth' |
            Should -Be 'pwsh -NoLogo -NoExit -Command "Clear-Host; wtw --on at go auth"'
    }

    It 'prefixes the host identity and does not resolve a missing name' {
        InModuleScope wtw -Parameters @{ HostEntry = $script:remoteHost } {
            Mock Get-WtwRemoteTarget { throw 'home sessions do not resolve a remote target' }

            $session = Resolve-WtwCmuxRemoteSession -HostEntry $HostEntry -HostSelector 'at'
            $session.PrettyName | Should -Be '🧊AT.at'
            $session.StatusValue | Should -Be 'wtw-remote: at'
            $session.Command | Should -Be 'pwsh -NoLogo -NoExit -Command "Clear-Host; wtw --on at go"'
            $session.ShellInitCommand | Should -Be 'clear; wtw --on at go'
            $session.RemotePath | Should -BeNullOrEmpty
        }
    }

    It 'uses the remote pretty name when a worktree is named' {
        InModuleScope wtw -Parameters @{ HostEntry = $script:remoteHost } {
            Mock Get-WtwRemoteTarget {
                @{
                    Path       = '/remote/app_auth'
                    Color      = '#336699'
                    Title      = 'app/auth'
                    PrettyName = '🟢 Auth'
                }
            }

            $session = Resolve-WtwCmuxRemoteSession -HostEntry $HostEntry -HostSelector 'at' -Name 'auth'
            $session.PrettyName | Should -Be '🧊AT.🟢 Auth'
            $session.StatusValue | Should -Be 'wtw-remote: at/app/auth'
            $session.Color | Should -Be '#336699'
            $session.RemotePath | Should -Be '/remote/app_auth'
            $session.ShellInitCommand | Should -Be 'clear; wtw --on at go auth'
        }
    }

    It 'matches remote workspaces by title or description, never by shared home cwd' {
        InModuleScope wtw {
            $home = if ($HOME) { [System.IO.Path]::GetFullPath($HOME) } else { (Get-Location).Path }
            Mock Get-WtwCmuxLiveWorkspaces {
                @(
                    [PSCustomObject]@{
                        ref         = 'workspace:home'
                        title       = 'unrelated home tab'
                        cwd         = $home
                        description = 'local shell'
                    }
                    [PSCustomObject]@{
                        ref         = 'workspace:remote'
                        title       = '🧊AT.🟢 Auth'
                        cwd         = $home
                        description = 'wtw-remote: at/app/auth'
                    }
                )
            }

            $byTitle = Find-WtwCmuxRemoteWorkspace -PrettyName '🧊AT.🟢 Auth' -StatusValue 'wtw-remote: at/app/auth'
            $byTitle.ref | Should -Be 'workspace:remote'

            $byDescription = Find-WtwCmuxRemoteWorkspace -PrettyName 'stale title' -StatusValue 'wtw-remote: at/app/auth'
            $byDescription.ref | Should -Be 'workspace:remote'

            $miss = Find-WtwCmuxRemoteWorkspace -PrettyName '🧊AT.other' -StatusValue 'wtw-remote: other'
            $miss | Should -BeNullOrEmpty
        }
    }

    It 'prints the cmux create line without contacting cmux' {
        InModuleScope wtw -Parameters @{ HostEntry = $script:remoteHost } {
            Mock Get-WtwRemoteTarget {
                @{
                    Path       = '/remote/app_auth'
                    Color      = $null
                    Title      = 'app/auth'
                    PrettyName = 'Auth'
                }
            }
            Mock Test-WtwCmuxPresent { throw 'print-only must not require cmux' }
            Mock Invoke-WtwCmuxCommand { throw 'print-only must not invoke cmux' }

            $out = Open-WtwCmuxRemoteWorkspace -HostEntry $HostEntry -HostSelector 'at' -Name 'auth' -Via 'tailscale' -PrintOnly 6>&1 | Out-String
            $out | Should -Match 'new-workspace --name 🧊AT.Auth'
            $out | Should -Match 'wtw --on at --via tailscale go auth'
        }
    }

    It 'creates a home-cwd remote workspace instead of selecting an unrelated home tab' {
        InModuleScope wtw -Parameters @{ HostEntry = $script:remoteHost } {
            $script:cmuxCalls = [System.Collections.Generic.List[string]]::new()
            Mock Test-WtwCmuxPresent { $true }
            Mock Open-WtwCmuxAppleScriptWorkspace { $false }
            Mock Invoke-WtwCmuxCommand {
                $script:cmuxCalls.Add(($ArgumentList -join ' '))
                $command = $ArgumentList -join ' '
                if ($command -eq 'list-workspaces --json') {
                    $home = if ($HOME) { [System.IO.Path]::GetFullPath($HOME).Replace('\', '\\') } else { '' }
                    return [PSCustomObject]@{
                        ExitCode = 0
                        Output   = @"
{
  "workspaces": [
    {
      "ref": "workspace:home",
      "title": "unrelated home tab",
      "current_directory": "$home"
    }
  ]
}
"@
                    }
                }
                if ($command -eq 'current-workspace') {
                    return [PSCustomObject]@{ ExitCode = 0; Output = 'workspace:remote' }
                }
                return [PSCustomObject]@{ ExitCode = 0; Output = '' }
            }

            Open-WtwCmuxRemoteWorkspace -HostEntry $HostEntry -HostSelector 'at'

            @($script:cmuxCalls | Where-Object { $_ -like 'select-workspace*' }).Count | Should -Be 0
            $create = $script:cmuxCalls | Where-Object { $_ -like 'new-workspace *' } | Select-Object -First 1
            $create | Should -Match '--name 🧊AT.at'
            $create | Should -Match '--command pwsh -NoLogo -NoExit -Command "Clear-Host; wtw --on at go"'
            $create | Should -Match '--description wtw-remote: at'
        }
    }

    It 'types a POSIX remote command into AppleScript fallback, not PowerShell' {
        InModuleScope wtw -Parameters @{ HostEntry = $script:remoteHost } {
            Mock Get-WtwRemoteTarget {
                @{
                    Path       = '/remote/app_auth'
                    Color      = $null
                    Title      = 'app/auth'
                    PrettyName = 'Auth'
                }
            }
            Mock Test-WtwCmuxPresent { $true }
            Mock Invoke-WtwCmuxCommand {
                return [PSCustomObject]@{
                    ExitCode = 1
                    Output   = 'Error: ERROR: Access denied - only processes started inside cmux can connect'
                }
            }
            Mock Open-WtwCmuxAppleScriptWorkspace { $true }

            Open-WtwCmuxRemoteWorkspace -HostEntry $HostEntry -HostSelector 'at' -Name 'auth'

            Should -Invoke Open-WtwCmuxAppleScriptWorkspace -Times 1 -Exactly -ParameterFilter {
                $MatchByNameOnly -and
                $InitCommand -eq 'clear; wtw --on at go auth'
            }
        }
    }

    It 'selects an existing remote workspace by description' {
        InModuleScope wtw -Parameters @{ HostEntry = $script:remoteHost } {
            $script:cmuxCalls = [System.Collections.Generic.List[string]]::new()
            Mock Get-WtwRemoteTarget {
                @{
                    Path       = '/remote/app_auth'
                    Color      = '#336699'
                    Title      = 'app/auth'
                    PrettyName = '🟢 Auth'
                }
            }
            Mock Test-WtwCmuxPresent { $true }
            Mock Invoke-WtwCmuxCommand {
                $script:cmuxCalls.Add(($ArgumentList -join ' '))
                $command = $ArgumentList -join ' '
                if ($command -eq 'list-workspaces --json') {
                    return [PSCustomObject]@{
                        ExitCode = 0
                        Output   = @'
{
  "workspaces": [
    {
      "ref": "workspace:remote",
      "title": "stale remote title",
      "description": "wtw-remote: at/app/auth"
    }
  ]
}
'@
                    }
                }
                return [PSCustomObject]@{ ExitCode = 0; Output = '' }
            }

            Open-WtwCmuxRemoteWorkspace -HostEntry $HostEntry -HostSelector 'at' -Name 'auth'

            $script:cmuxCalls | Should -Contain 'select-workspace --workspace workspace:remote'
            @($script:cmuxCalls | Where-Object { $_ -like 'new-workspace*' }).Count | Should -Be 0
            $script:cmuxCalls | Should -Contain 'workspace-action --workspace workspace:remote --action rename --title 🧊AT.🟢 Auth'
        }
    }
}
