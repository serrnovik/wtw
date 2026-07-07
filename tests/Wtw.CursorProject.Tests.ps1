BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Cursor project integration' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-cursor-" + [guid]::NewGuid())
        $script:workspacePath = Join-Path $script:tempDir 'repo_feature.code-workspace'
        $script:statePath = Join-Path $script:tempDir 'Cursor/User/globalStorage/state.vscdb'
        New-Item -ItemType Directory -Path (Split-Path $script:workspacePath -Parent), (Split-Path $script:statePath -Parent) -Force | Out-Null
        Set-Content -Path $script:workspacePath -Value '{"folders":[],"settings":{}}' -Encoding utf8
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:tempDir -ErrorAction SilentlyContinue
    }

    It 'creates a deterministic workspace id' {
        $id = ConvertTo-WtwCursorWorkspaceId -WorkspacePath $script:workspacePath

        $id | Should -Match '^[0-9a-f]{32}$'
        ConvertTo-WtwCursorWorkspaceId -WorkspacePath $script:workspacePath | Should -Be $id
    }

    It 'prepends and deduplicates Cursor recent workspaces' -Skip:(-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
        $existingWorkspace = Join-Path $script:tempDir 'other.code-workspace'
        Set-Content -Path $existingWorkspace -Value '{}'
        Set-WtwCursorRecentWorkspace -WorkspacePath $existingWorkspace -StatePath $script:statePath | Should -BeTrue

        Set-WtwCursorRecentWorkspace -WorkspacePath $script:workspacePath -StatePath $script:statePath | Should -BeTrue
        Set-WtwCursorRecentWorkspace -WorkspacePath $script:workspacePath -StatePath $script:statePath | Should -BeTrue

        $state = Read-WtwCursorRecentlyOpenedState -StatePath $script:statePath
        $workspaceUri = ConvertTo-WtwFileUri -Path $script:workspacePath
        $matching = @($state.entries | Where-Object { $_.workspace.configPath -eq $workspaceUri })

        $state.entries[0].workspace.configPath | Should -Be $workspaceUri
        $matching.Count | Should -Be 1
        $state.entries.Count | Should -Be 2
    }

    It 'removes a matching Cursor recent workspace' -Skip:(-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
        $existingWorkspace = Join-Path $script:tempDir 'other.code-workspace'
        Set-Content -Path $existingWorkspace -Value '{}'
        Set-WtwCursorRecentWorkspace -WorkspacePath $existingWorkspace -StatePath $script:statePath | Should -BeTrue
        Set-WtwCursorRecentWorkspace -WorkspacePath $script:workspacePath -StatePath $script:statePath | Should -BeTrue

        Remove-WtwCursorRecentWorkspace -WorkspacePath $script:workspacePath -StatePath $script:statePath | Should -BeTrue

        $state = Read-WtwCursorRecentlyOpenedState -StatePath $script:statePath
        $workspaceUri = ConvertTo-WtwFileUri -Path $script:workspacePath
        $otherUri = ConvertTo-WtwFileUri -Path $existingWorkspace

        @($state.entries | Where-Object { $_.workspace.configPath -eq $workspaceUri }).Count | Should -Be 0
        @($state.entries | Where-Object { $_.workspace.configPath -eq $otherUri }).Count | Should -Be 1
    }

    It 'registers an existing workspace when Cursor is present' {
        Mock Test-WtwCursorPresent { $true }
        Mock Set-WtwCursorRecentWorkspace { $true }

        Register-WtwCursorProject -WorkspacePath $script:workspacePath -PrettyName 'Blue Feature' -Color '#336699' |
            Should -Be ([System.IO.Path]::GetFullPath($script:workspacePath))

        Should -Invoke Set-WtwCursorRecentWorkspace -Times 1 -Exactly -ParameterFilter {
            $WorkspacePath -eq $script:workspacePath
        }
    }
}
