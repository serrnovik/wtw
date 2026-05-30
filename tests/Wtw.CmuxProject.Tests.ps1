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

        Should -Invoke Invoke-WtwCmuxCommand -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -join ' ') -eq 'reload-config'
        }
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

Describe 'Open-WtwCmuxWorkspace' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-cmux-open-" + [guid]::NewGuid())
        $script:projectPath = Join-Path $script:tempDir 'repo_feature'
        New-Item -ItemType Directory -Path $script:projectPath -Force | Out-Null
        $script:cmuxCalls = [System.Collections.Generic.List[string]]::new()

        Mock Test-WtwCmuxPresent { $true } -ModuleName wtw
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:tempDir -ErrorAction SilentlyContinue
    }

    It 'selects an existing cmux workspace by cwd' {
        Mock Invoke-WtwCmuxCommand {
            $script:cmuxCalls.Add(($ArgumentList -join ' '))
            $command = $ArgumentList -join ' '
            if ($command -eq '--json list-workspaces') {
                return [PSCustomObject]@{
                    ExitCode = 0
                    Output   = (@{
                        workspaces = @(
                            @{
                                ref  = 'workspace:2'
                                name = 'Blue Feature'
                                cwd  = $script:projectPath
                            }
                        )
                    } | ConvertTo-Json -Depth 10 -Compress)
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
        $script:cmuxCalls | Should -Contain 'workspace-action --workspace workspace:2 --action set-color --color #336699'
        $script:cmuxCalls | Should -Contain 'set-status wtw repo/feature --workspace workspace:2 --icon git-branch --color #336699 --priority 90'
    }

    It 'creates a named cwd workspace when none is already open' {
        Mock Invoke-WtwCmuxCommand {
            $script:cmuxCalls.Add(($ArgumentList -join ' '))
            $command = $ArgumentList -join ' '
            if ($command -eq '--json list-workspaces') {
                return [PSCustomObject]@{ ExitCode = 0; Output = '{"workspaces":[]}' }
            }
            if ($command -eq '--json current-workspace') {
                return [PSCustomObject]@{ ExitCode = 0; Output = '{"ref":"workspace:4","name":"Green Feature"}' }
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
        $script:cmuxCalls | Should -Contain 'workspace-action --workspace workspace:4 --action rename --title Green Feature'
        $script:cmuxCalls | Should -Contain 'workspace-action --workspace workspace:4 --action set-color --color #228833'
    }
}
