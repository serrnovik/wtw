BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
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
workspace:1 Main
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
        Mock Register-WtwCmuxProject { 'wtw.test' } -ModuleName wtw
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:tempDir -ErrorAction SilentlyContinue
    }

    It 'selects an existing cmux workspace by cwd' {
        Mock Invoke-WtwCmuxCommand {
            $script:cmuxCalls.Add(($ArgumentList -join ' '))
            $command = $ArgumentList -join ' '
            if ($command -eq 'list-workspaces') {
                return [PSCustomObject]@{
                    ExitCode = 0
                    Output   = "workspace:2 Blue Feature"
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

        $script:cmuxCalls | Should -Contain 'select-workspace --workspace workspace:2'
        ($script:cmuxCalls | Where-Object { $_ -like 'new-workspace*' }).Count | Should -Be 0
        ($script:cmuxCalls | Where-Object { $_ -eq 'workspace-action --workspace workspace:2 --action rename --title Blue Feature' }).Count | Should -Be 0
        $script:cmuxCalls | Should -Contain 'workspace-action --workspace workspace:2 --action set-color --color #336699'
        $script:cmuxCalls | Should -Contain 'set-status wtw repo/feature --workspace workspace:2 --icon git-branch --color #336699 --priority 90'
    }

    It 'creates a named cwd workspace when none is already open' {
        Mock Invoke-WtwCmuxCommand {
            $script:cmuxCalls.Add(($ArgumentList -join ' '))
            $command = $ArgumentList -join ' '
            if ($command -eq 'list-workspaces') {
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

        $script:cmuxCalls | Should -Contain "new-workspace --name Green Feature --cwd $script:projectPath --focus true --description wtw: repo/green"
        ($script:cmuxCalls | Where-Object { $_ -eq 'workspace-action --workspace workspace:4 --action rename --title Green Feature' }).Count | Should -Be 0
        $script:cmuxCalls | Should -Contain 'workspace-action --workspace workspace:4 --action set-color --color #228833'
    }

    It 'falls back to macOS app open when socket workspace creation is denied' {
        Mock Invoke-WtwCmuxCommand {
            $script:cmuxCalls.Add(($ArgumentList -join ' '))
            $command = $ArgumentList -join ' '
            if ($command -eq 'list-workspaces') {
                return [PSCustomObject]@{ ExitCode = 1; Output = 'Error: ERROR: Access denied - only processes started inside cmux can connect' }
            }
            if ($command -like 'new-workspace*') {
                return [PSCustomObject]@{ ExitCode = 1; Output = 'Error: ERROR: Access denied - only processes started inside cmux can connect' }
            }
            return [PSCustomObject]@{ ExitCode = 0; Output = '' }
        } -ModuleName wtw

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

        Should -Invoke Open-WtwCmuxAppPath -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
            $ProjectPath -eq $script:projectPath
        }
        $script:cmuxCalls | Should -Contain "new-workspace --name Denied Feature --cwd $script:projectPath --focus true --description wtw: repo/denied"
        ($script:cmuxCalls | Where-Object { $_ -eq $script:projectPath }).Count | Should -Be 0
    }
}

Describe 'cmux shell startup metadata hook' {
    It 'applies pretty name and color to the current cmux workspace' {
        $oldWorkspaceId = $env:CMUX_WORKSPACE_ID
        try {
            $env:CMUX_WORKSPACE_ID = 'workspace:9'
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
            Mock Set-WtwCmuxWorkspaceMetadata {} -ModuleName wtw

            Invoke-Wtw __cmux_apply_current

            Should -Invoke Set-WtwCmuxWorkspaceMetadata -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
                $WorkspaceRef -eq 'workspace:9' -and
                $PrettyName -eq '🟢 Feature' -and
                $Color -eq '#96dd2c' -and
                $StatusValue -eq 'repo/feature'
            }
        } finally {
            $env:CMUX_WORKSPACE_ID = $oldWorkspaceId
        }
    }
}
