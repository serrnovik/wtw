BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
    $script:originalBackupRoot = $env:WTW_BACKUP_ROOT
    $env:WTW_BACKUP_ROOT = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-bak-codex-" + [guid]::NewGuid())
}

AfterAll {
    if ($env:WTW_BACKUP_ROOT -and (Test-Path $env:WTW_BACKUP_ROOT)) {
        Remove-Item -Recurse -Force $env:WTW_BACKUP_ROOT -ErrorAction SilentlyContinue
    }
    $env:WTW_BACKUP_ROOT = $script:originalBackupRoot
}

Describe 'Codex project integration' {
    It 'resolves only a real Codex executable, not a shell alias' {
        Mock Get-Command {
            [PSCustomObject]@{ Source = '/opt/tools/codex' }
        } -ParameterFilter { $Name -eq 'codex' -and $CommandType -eq 'Application' }

        Get-WtwCodexCliPath | Should -Be '/opt/tools/codex'
        Should -Invoke Get-Command -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'codex' -and $CommandType -eq 'Application'
        }
    }

    It 'prefers the renamed ChatGPT app over the legacy Codex app on macOS' {
        Mock Test-Path { $Path -in '/Applications/ChatGPT.app', '/Applications/Codex.app' }

        Get-WtwCodexMacAppName | Should -Be 'ChatGPT'
    }

    It 'falls back to the legacy Codex app name on macOS' {
        Mock Test-Path { $Path -eq '/Applications/Codex.app' }

        Get-WtwCodexMacAppName | Should -Be 'Codex'
    }

    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-codex-" + [guid]::NewGuid())
        $script:codexHome = Join-Path $script:tempDir '.codex'
        $script:projectPath = Join-Path $script:tempDir 'repo_feature'
        New-Item -ItemType Directory -Path $script:codexHome, $script:projectPath -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:tempDir -ErrorAction SilentlyContinue
    }

    It 'adds and removes a trusted project section' {
        $configPath = Join-Path $script:codexHome 'config.toml'
        Set-Content -Path $configPath -Value "model = `"gpt-5.5`"`n" -Encoding utf8

        Set-WtwCodexProjectTrust -ProjectPath $script:projectPath -ConfigPath $configPath
        $content = Get-Content -Path $configPath -Raw

        $content | Should -Match ([regex]::Escape("[projects.`"$script:projectPath`"]"))
        $content | Should -Match 'trust_level = "trusted"'

        Remove-WtwCodexProjectTrust -ProjectPath $script:projectPath -ConfigPath $configPath
        $content = Get-Content -Path $configPath -Raw

        $content | Should -Not -Match ([regex]::Escape("[projects.`"$script:projectPath`"]"))
    }

    It 'updates Codex desktop roots and labels' {
        $statePath = Join-Path $script:codexHome '.codex-global-state.json'
        @{
            'electron-saved-workspace-roots' = @('/existing')
            'project-order' = @('/existing')
            'electron-workspace-root-labels' = @{}
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $statePath -Encoding utf8

        Set-WtwCodexProjectLabel -ProjectPath $script:projectPath -PrettyName 'Blue Feature' -GlobalStatePath $statePath | Should -BeTrue
        $state = Get-Content -Path $statePath -Raw | ConvertFrom-Json
        $localProject = @($state.'local-projects'.PSObject.Properties | Where-Object { $_.Value.rootPaths -contains $script:projectPath })[0]

        @($state.'electron-saved-workspace-roots')[0] | Should -Be $script:projectPath
        @($state.'project-order')[0] | Should -Be $localProject.Name
        @($state.'project-order') | Should -Not -Contain $script:projectPath
        $state.'electron-workspace-root-labels'.PSObject.Properties[$script:projectPath].Value | Should -Be 'Blue Feature'
        $localProject.Value.name | Should -Be 'Blue Feature'
        $localProject.Value.id | Should -Be $localProject.Name

        Remove-WtwCodexProjectLabel -ProjectPath $script:projectPath -GlobalStatePath $statePath | Should -BeTrue
        $state = Get-Content -Path $statePath -Raw | ConvertFrom-Json

        @($state.'electron-saved-workspace-roots') | Should -Not -Contain $script:projectPath
        @($state.'project-order') | Should -Not -Contain $script:projectPath
        $state.'local-projects'.PSObject.Properties.Name | Should -Not -Contain $localProject.Name
        $state.'electron-workspace-root-labels'.PSObject.Properties.Name | Should -Not -Contain $script:projectPath
    }

    It 'renames the existing ChatGPT Desktop local project for a worktree' {
        $statePath = Join-Path $script:codexHome '.codex-global-state.json'
        $projectId = [guid]::NewGuid().ToString()
        [PSCustomObject]@{
            'local-projects' = [PSCustomObject]@{
                $projectId = [PSCustomObject]@{
                    id = 'stale-id'
                    name = 'repo_feature'
                    rootPaths = @($script:projectPath)
                    createdAt = 100
                    updatedAt = 100
                }
            }
            'project-order' = @($projectId, $script:projectPath)
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $statePath -Encoding utf8

        Set-WtwCodexProjectLabel -ProjectPath $script:projectPath -PrettyName '🟠 Feature Worktree' -GlobalStatePath $statePath | Should -BeTrue
        $state = Get-Content -Path $statePath -Raw | ConvertFrom-Json

        $state.'local-projects'.PSObject.Properties[$projectId].Value.id | Should -Be $projectId
        $state.'local-projects'.PSObject.Properties[$projectId].Value.name | Should -Be '🟠 Feature Worktree'
        $state.'local-projects'.PSObject.Properties.Count | Should -Be 1
        @($state.'project-order') | Should -Be @($projectId)
        Get-WtwCodexProjectLabel -ProjectPath $script:projectPath -GlobalStatePath $statePath | Should -Be '🟠 Feature Worktree'
    }

    It 'matches normalized roots and preserves the rest of a multi-root project' {
        $statePath = Join-Path $script:codexHome '.codex-global-state.json'
        $projectId = [guid]::NewGuid().ToString()
        $alternateRoot = Join-Path $script:tempDir 'shared-root'
        [PSCustomObject]@{
            'local-projects' = [PSCustomObject]@{
                $projectId = [PSCustomObject]@{
                    id = $projectId
                    name = 'Shared Project'
                    rootPaths = @("$script:projectPath/", $alternateRoot)
                }
            }
            'project-order' = @($projectId)
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $statePath -Encoding utf8

        Get-WtwCodexProjectLabel -ProjectPath $script:projectPath -GlobalStatePath $statePath | Should -Be 'Shared Project'
        Remove-WtwCodexProjectLabel -ProjectPath $script:projectPath -GlobalStatePath $statePath | Should -BeTrue
        $state = Get-Content -Path $statePath -Raw | ConvertFrom-Json

        $state.'local-projects'.PSObject.Properties[$projectId].Value.rootPaths | Should -Be @($alternateRoot)
        @($state.'project-order') | Should -Contain $projectId
    }

    It 'does not treat a legacy label as a complete modern project label' {
        $statePath = Join-Path $script:codexHome '.codex-global-state.json'
        [PSCustomObject]@{
            'electron-workspace-root-labels' = [PSCustomObject]@{
                $script:projectPath = 'Legacy Label'
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $statePath -Encoding utf8

        Get-WtwCodexProjectLabel -ProjectPath $script:projectPath -GlobalStatePath $statePath | Should -Be 'Legacy Label'
        Test-WtwCodexProjectLabel -ProjectPath $script:projectPath -PrettyName 'Legacy Label' -GlobalStatePath $statePath |
            Should -BeFalse
    }

    It 'creates Codex desktop state when it is missing' {
        $statePath = Join-Path $script:codexHome '.codex-global-state.json'

        Set-WtwCodexProjectLabel -ProjectPath $script:projectPath -PrettyName 'Fresh State' -GlobalStatePath $statePath | Should -BeTrue
        $state = Get-Content -Path $statePath -Raw | ConvertFrom-Json

        @($state.'electron-saved-workspace-roots') | Should -Contain $script:projectPath
        $localProject = @($state.'local-projects'.PSObject.Properties | Where-Object {
            @($_.Value.rootPaths) -contains $script:projectPath
        })[0]
        @($state.'project-order') | Should -Contain $localProject.Name
        @($state.'project-order') | Should -Not -Contain $script:projectPath
        $state.'electron-workspace-root-labels'.PSObject.Properties[$script:projectPath].Value | Should -Be 'Fresh State'
        @($state.'local-projects'.PSObject.Properties | Where-Object { $_.Value.rootPaths -contains $script:projectPath }).Value.name | Should -Be 'Fresh State'
    }

    It 'detects when Codex desktop label is already present' {
        $statePath = Join-Path $script:codexHome '.codex-global-state.json'

        Set-WtwCodexProjectLabel -ProjectPath $script:projectPath -PrettyName 'Existing Label' -GlobalStatePath $statePath | Should -BeTrue

        Get-WtwCodexProjectLabel -ProjectPath $script:projectPath -GlobalStatePath $statePath | Should -Be 'Existing Label'
        Test-WtwCodexProjectLabel -ProjectPath $script:projectPath -PrettyName 'Existing Label' -GlobalStatePath $statePath | Should -BeTrue
        Test-WtwCodexProjectLabel -ProjectPath $script:projectPath -PrettyName 'Other Label' -GlobalStatePath $statePath | Should -BeFalse
    }

    It 'registers a project when CODEX_HOME exists' {
        $oldCodexHome = $env:CODEX_HOME
        try {
            $env:CODEX_HOME = $script:codexHome
            Mock Test-WtwCodexAppRunning { $false }
            @{ 'electron-saved-workspace-roots' = @(); 'project-order' = @() } |
                ConvertTo-Json -Depth 10 |
                Set-Content -Path (Join-Path $script:codexHome '.codex-global-state.json') -Encoding utf8

            Register-WtwCodexProject -ProjectPath $script:projectPath -PrettyName 'Green Feature' | Should -Be $script:projectPath

            Test-Path (Join-Path $script:projectPath '.codex/config.toml') | Should -BeTrue
            Get-Content -Path (Join-Path $script:codexHome 'config.toml') -Raw | Should -Match 'trust_level = "trusted"'
            $state = Get-Content -Path (Join-Path $script:codexHome '.codex-global-state.json') -Raw | ConvertFrom-Json
            $state.'electron-workspace-root-labels'.PSObject.Properties[$script:projectPath].Value | Should -Be 'Green Feature'
        } finally {
            $env:CODEX_HOME = $oldCodexHome
        }
    }

    It 'defers desktop label state while Codex is already running' {
        $oldCodexHome = $env:CODEX_HOME
        try {
            $env:CODEX_HOME = $script:codexHome
            Mock Test-WtwCodexAppRunning { $true }
            @{ 'electron-saved-workspace-roots' = @(); 'project-order' = @() } |
                ConvertTo-Json -Depth 10 |
                Set-Content -Path (Join-Path $script:codexHome '.codex-global-state.json') -Encoding utf8

            Register-WtwCodexProject -ProjectPath $script:projectPath -PrettyName 'Running App' | Should -Be $script:projectPath

            $state = Get-Content -Path (Join-Path $script:codexHome '.codex-global-state.json') -Raw | ConvertFrom-Json
            @($state.'electron-saved-workspace-roots') | Should -Not -Contain $script:projectPath
            $state.PSObject.Properties.Name | Should -Not -Contain 'electron-workspace-root-labels'
        } finally {
            $env:CODEX_HOME = $oldCodexHome
        }
    }

    It 'can force-close Codex before writing project label state' {
        Mock Test-WtwCodexAppRunning { $true }
        Mock Read-Host { 'k' }
        Mock Stop-WtwCodexProcess { $true }

        $decision = Resolve-WtwCodexStateConflict -OperationLabel 'set sidebar label'

        $decision.proceed | Should -BeTrue
        $decision.relaunch | Should -BeTrue
        Should -Invoke Stop-WtwCodexProcess -Times 1 -Exactly
    }
}

Describe 'Codex project state under the module StrictMode' {
    # These run through InModuleScope rather than the dot-sourced copies the
    # Describe above uses. wtw.psm1 sets StrictMode -Version Latest, and a
    # dot-sourced function called from test scope does not inherit it — which is
    # how `@(<empty pipeline>)[0]` survived here: harmless in the tests, fatal
    # from the real CLI, and only on the path that matters, registering a
    # worktree Codex has never seen.

    BeforeEach {
        $script:strictTempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-codex-strict-" + [guid]::NewGuid())
        $script:strictCodexHome = Join-Path $script:strictTempDir '.codex'
        $script:strictProjectPath = Join-Path $script:strictTempDir 'repo_new-worktree'
        New-Item -ItemType Directory -Path $script:strictCodexHome, $script:strictProjectPath -Force | Out-Null

        # A state file that already knows about a different project: the shape of
        # every real machine, and the one that used to throw.
        $script:strictStatePath = Join-Path $script:strictCodexHome '.codex-global-state.json'
        [PSCustomObject]@{
            'local-projects' = [PSCustomObject]@{
                ([guid]::NewGuid().ToString()) = [PSCustomObject]@{
                    id        = 'someone-else'
                    name      = 'unrelated project'
                    rootPaths = @((Join-Path $script:strictTempDir 'some_other_repo'))
                    createdAt = 100
                    updatedAt = 100
                }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:strictStatePath -Encoding utf8
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:strictTempDir -ErrorAction SilentlyContinue
    }

    It 'labels a project the state has never seen' {
        InModuleScope wtw -Parameters @{ StatePath = $script:strictStatePath; ProjectPath = $script:strictProjectPath } {
            param($StatePath, $ProjectPath)
            { Set-WtwCodexProjectLabel -ProjectPath $ProjectPath -PrettyName '🔴 🐙 argocd' -GlobalStatePath $StatePath } |
                Should -Not -Throw
            Get-WtwCodexProjectLabel -ProjectPath $ProjectPath -GlobalStatePath $StatePath | Should -Be '🔴 🐙 argocd'
        }
    }

    It 'reports an unregistered project as unlabelled instead of throwing' {
        InModuleScope wtw -Parameters @{ StatePath = $script:strictStatePath; ProjectPath = $script:strictProjectPath } {
            param($StatePath, $ProjectPath)
            Get-WtwCodexProjectLabel -ProjectPath $ProjectPath -GlobalStatePath $StatePath | Should -BeNullOrEmpty
            Test-WtwCodexProjectLabel -ProjectPath $ProjectPath -PrettyName 'anything' -GlobalStatePath $StatePath |
                Should -BeFalse
        }
    }

    It 'keeps the unrelated project it found alongside the new one' {
        InModuleScope wtw -Parameters @{ StatePath = $script:strictStatePath; ProjectPath = $script:strictProjectPath } {
            param($StatePath, $ProjectPath)
            Set-WtwCodexProjectLabel -ProjectPath $ProjectPath -PrettyName 'New One' -GlobalStatePath $StatePath | Out-Null

            $state = Get-Content -Path $StatePath -Raw | ConvertFrom-Json
            $names = @($state.'local-projects'.PSObject.Properties.Value.name)
            $names | Should -Contain 'unrelated project'
            $names | Should -Contain 'New One'
        }
    }

    It 'removes a single-root project without reading Count on null' {
        InModuleScope wtw -Parameters @{ StatePath = $script:strictStatePath; ProjectPath = $script:strictProjectPath } {
            param($StatePath, $ProjectPath)
            Set-WtwCodexProjectLabel -ProjectPath $ProjectPath -PrettyName 'To Delete' -GlobalStatePath $StatePath | Out-Null

            { Remove-WtwCodexProjectLabel -ProjectPath $ProjectPath -GlobalStatePath $StatePath } |
                Should -Not -Throw
            Get-WtwCodexProjectLabel -ProjectPath $ProjectPath -GlobalStatePath $StatePath | Should -BeNullOrEmpty

            $state = Get-Content -Path $StatePath -Raw | ConvertFrom-Json
            @($state.'local-projects'.PSObject.Properties.Value.name) | Should -Contain 'unrelated project'
            @($state.'local-projects'.PSObject.Properties.Value.name) | Should -Not -Contain 'To Delete'
        }
    }

    It 'keeps a multi-root project after dropping one root' {
        InModuleScope wtw -Parameters @{
            StatePath = $script:strictStatePath
            ProjectPath = $script:strictProjectPath
            AlternateRoot = (Join-Path $script:strictTempDir 'shared-root')
        } {
            param($StatePath, $ProjectPath, $AlternateRoot)
            $projectId = [guid]::NewGuid().ToString()
            $state = Get-Content -Path $StatePath -Raw | ConvertFrom-Json
            $state.'local-projects' | Add-Member -NotePropertyName $projectId -NotePropertyValue ([PSCustomObject]@{
                id        = $projectId
                name      = 'Shared Project'
                rootPaths = @($ProjectPath, $AlternateRoot)
            }) -Force
            $state | ConvertTo-Json -Depth 10 | Set-Content -Path $StatePath -Encoding utf8

            { Remove-WtwCodexProjectLabel -ProjectPath $ProjectPath -GlobalStatePath $StatePath } |
                Should -Not -Throw

            $state = Get-Content -Path $StatePath -Raw | ConvertFrom-Json
            $state.'local-projects'.PSObject.Properties[$projectId].Value.rootPaths | Should -Be @($AlternateRoot)
        }
    }
}
