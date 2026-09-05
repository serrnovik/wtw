BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
    $script:originalBackupRoot = $env:WTW_BACKUP_ROOT
    $env:WTW_BACKUP_ROOT = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-bak-cursor-" + [guid]::NewGuid())
}

AfterAll {
    if ($env:WTW_BACKUP_ROOT -and (Test-Path $env:WTW_BACKUP_ROOT)) {
        Remove-Item -Recurse -Force $env:WTW_BACKUP_ROOT -ErrorAction SilentlyContinue
    }
    $env:WTW_BACKUP_ROOT = $script:originalBackupRoot
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

    It 'handles a Get-Process runtime failure without printing an error' {
        Mock Get-Process { throw 'FileVersionInfo is unavailable' }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'pgrep' }

        { Test-WtwCursorAppRunning } | Should -Not -Throw
        Test-WtwCursorAppRunning | Should -BeFalse
    }

    It 'creates a deterministic workspace id' {
        $id = ConvertTo-WtwCursorWorkspaceId -WorkspacePath $script:workspacePath

        $id | Should -Match '^[0-9a-f]{32}$'
        ConvertTo-WtwCursorWorkspaceId -WorkspacePath $script:workspacePath | Should -Be $id
    }

    It 'matches Cursor saved-workspace MD5 identity rules' {
        $fullPath = [System.IO.Path]::GetFullPath($script:workspacePath)
        $hashInput = if ($IsLinux) { $fullPath } else { $fullPath.ToLowerInvariant() }
        $expectedHash = [System.Security.Cryptography.MD5]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($hashInput)
        )
        $expected = -join ($expectedHash | ForEach-Object { $_.ToString('x2') })

        ConvertTo-WtwCursorWorkspaceId -WorkspacePath $script:workspacePath | Should -Be $expected
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

    It 'migrates an existing Agents workspace label without losing project membership' -Skip:(-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
        $dataHome = Join-Path $script:tempDir 'Cursor'
        $statePath = Join-Path $dataHome 'User/globalStorage/state.vscdb'
        $storageJsonPath = Join-Path $dataHome 'User/globalStorage/storage.json'
        New-Item -ItemType Directory -Path (Split-Path $statePath -Parent) -Force | Out-Null

        $oldId = ConvertTo-WtwCursorWorkspaceId -WorkspacePath $script:workspacePath
        $prettyPath = Join-Path $script:tempDir '🟠 Blue Feature.code-workspace'
        $newId = ConvertTo-WtwCursorWorkspaceId -WorkspacePath $prettyPath
        $oldUri = ConvertTo-WtwFileUri -Path $script:workspacePath
        $oldStoragePath = Join-Path $dataHome "User/workspaceStorage/$oldId"
        New-Item -ItemType Directory -Path $oldStoragePath -Force | Out-Null
        @{ workspace = $oldUri } | ConvertTo-Json -Compress |
            Set-Content -LiteralPath (Join-Path $oldStoragePath 'workspace.json') -Encoding utf8
        Set-Content -LiteralPath (Join-Path $oldStoragePath 'preserved.txt') -Value 'agent state' -Encoding utf8
        @{ opened = $oldUri; workspaceId = $oldId } | ConvertTo-Json -Compress |
            Set-Content -LiteralPath $storageJsonPath -Encoding utf8

        $recent = @{ entries = @(@{ workspace = @{ id = $oldId; configPath = $oldUri } }) } | ConvertTo-Json -Depth 10 -Compress
        $projects = @(
            @{
                id = 'project-stable-id'
                name = 'Existing agent'
                workspace = @{
                    id = $oldId
                    configPath = @{
                        fsPath = $script:workspacePath
                        external = $oldUri
                        path = $script:workspacePath
                        scheme = 'file'
                    }
                }
                createdAt = 1
                lastUpdatedAt = 2
                isArchived = $false
            }
        ) | ConvertTo-Json -Depth 10 -Compress
        $membership = @{ 'agent-stable-id' = 'project-stable-id' } | ConvertTo-Json -Compress
        $metadata = @{ entries = @(@{ workspaceId = $oldId; configPath = $oldUri }) } | ConvertTo-Json -Depth 10 -Compress
        $marker = @{ 'cursor/glass.tabs.v2/state' = "$oldId|$oldUri" } | ConvertTo-Json -Compress
        $sqlite = Get-WtwSqliteCommand
        $sql = @(
            'create table ItemTable (key TEXT primary key, value BLOB);'
            "insert into ItemTable values ('history.recentlyOpenedPathsList', $(ConvertTo-WtwSqliteLiteral $recent));"
            "insert into ItemTable values ('glass.localAgentProjects.v1', $(ConvertTo-WtwSqliteLiteral $projects));"
            "insert into ItemTable values ('glass.localAgentProjectMembership.v1', $(ConvertTo-WtwSqliteLiteral $membership));"
            "insert into ItemTable values ('workspaceMetadata.entries', $(ConvertTo-WtwSqliteLiteral $metadata));"
            "insert into ItemTable values ('__`$__targetStorageMarker', $(ConvertTo-WtwSqliteLiteral $marker));"
            "insert into ItemTable values ('cursor/glass.tabs.v2/$oldId/state.json', 'preserved tab state');"
        ) -join [Environment]::NewLine
        & $sqlite $statePath $sql
        $LASTEXITCODE | Should -Be 0
        Mock Test-WtwCursorAppRunning { $false }

        $result = Move-WtwCursorWorkspaceForAgents `
            -WorkspacePath $script:workspacePath `
            -PrettyName '🟠 Blue Feature' `
            -DataHome $dataHome

        $result | Should -Be $prettyPath
        Test-Path $script:workspacePath | Should -BeFalse
        Test-Path $prettyPath | Should -BeTrue
        Test-Path (Join-Path $dataHome "User/workspaceStorage/$newId/preserved.txt") | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $dataHome "User/workspaceStorage/$newId/workspace.json") -Raw) |
            Should -Match ([regex]::Escape((ConvertTo-WtwFileUri -Path $prettyPath)))

        $migratedProjects = Read-WtwCursorStateValue -StatePath $statePath -Key 'glass.localAgentProjects.v1' | ConvertFrom-Json
        $migratedMembership = Read-WtwCursorStateValue -StatePath $statePath -Key 'glass.localAgentProjectMembership.v1' | ConvertFrom-Json
        $migratedProjects[0].id | Should -Be 'project-stable-id'
        $migratedProjects[0].workspace.id | Should -Be $newId
        $migratedProjects[0].workspace.configPath.fsPath | Should -Be $prettyPath
        $migratedMembership.'agent-stable-id' | Should -Be 'project-stable-id'

        $renamedTabKey = "cursor/glass.tabs.v2/$newId/state.json"
        Read-WtwCursorStateValue -StatePath $statePath -Key $renamedTabKey | Should -Be 'preserved tab state'
        (Get-Content -LiteralPath $storageJsonPath -Raw) | Should -Match $newId
        @(Get-ChildItem -Path (Join-Path $dataHome 'User/wtw-backups') -Recurse -Filter 'cursor-state-rows.json').Count |
            Should -Be 1
    }
}
