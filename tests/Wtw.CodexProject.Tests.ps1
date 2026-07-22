BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
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

    It 'creates Codex desktop state when it is missing' {
        $statePath = Join-Path $script:codexHome '.codex-global-state.json'

        Set-WtwCodexProjectLabel -ProjectPath $script:projectPath -PrettyName 'Fresh State' -GlobalStatePath $statePath | Should -BeTrue
        $state = Get-Content -Path $statePath -Raw | ConvertFrom-Json

        @($state.'electron-saved-workspace-roots') | Should -Contain $script:projectPath
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
