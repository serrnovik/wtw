function Get-WtwCursorDataHome {
    [CmdletBinding()]
    param()

    if ($env:CURSOR_USER_DATA_DIR) {
        return [System.IO.Path]::GetFullPath($env:CURSOR_USER_DATA_DIR)
    }

    if ($IsMacOS) {
        return [System.IO.Path]::GetFullPath((Join-Path $HOME 'Library/Application Support/Cursor'))
    }
    if ($IsWindows) {
        return [System.IO.Path]::GetFullPath((Join-Path $env:APPDATA 'Cursor'))
    }

    return [System.IO.Path]::GetFullPath((Join-Path $HOME '.config/Cursor'))
}

function Get-WtwCursorGlobalStatePath {
    [CmdletBinding()]
    param([string] $DataHome = (Get-WtwCursorDataHome))

    return [System.IO.Path]::GetFullPath((Join-Path $DataHome 'User/globalStorage/state.vscdb'))
}

function Test-WtwCursorPresent {
    [CmdletBinding()]
    param([string] $DataHome = (Get-WtwCursorDataHome))

    if (Get-Command cursor -ErrorAction SilentlyContinue) { return $true }
    if ($DataHome -and (Test-Path $DataHome)) { return $true }
    if ($IsMacOS -and (Test-Path '/Applications/Cursor.app')) { return $true }

    return $false
}

function ConvertTo-WtwFileUri {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    return ([System.Uri]::new($fullPath)).AbsoluteUri
}

function ConvertTo-WtwCursorWorkspaceId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $WorkspacePath)

    # VS Code/Cursor define saved-workspace identity as MD5(originalFSPath).
    # macOS and Windows normalize the path to lower-case; Linux does not.
    # This must match Cursor exactly because the id also names workspaceStorage.
    $hashInput = [System.IO.Path]::GetFullPath($WorkspacePath)
    if (-not $IsLinux) {
        $hashInput = $hashInput.ToLowerInvariant()
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($hashInput)
    $hash = [System.Security.Cryptography.MD5]::HashData($bytes)
    return (-join ($hash | ForEach-Object { $_.ToString('x2') }))
}

function ConvertTo-WtwSqliteLiteral {
    [CmdletBinding()]
    param([AllowNull()][string] $Value)

    if ($null -eq $Value) { return 'NULL' }
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-WtwSqliteCommand {
    [CmdletBinding()]
    param()

    return (Get-Command sqlite3 -ErrorAction SilentlyContinue)?.Source
}

function Read-WtwCursorStateValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $StatePath,
        [Parameter(Mandatory)][string] $Key
    )

    if (-not (Test-Path $StatePath)) { return $null }
    $sqlite = Get-WtwSqliteCommand
    if (-not $sqlite) { return $null }

    $keyLiteral = ConvertTo-WtwSqliteLiteral $Key
    $raw = & $sqlite -readonly $StatePath "select value from ItemTable where key = $keyLiteral limit 1;" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($raw -join [Environment]::NewLine)
}

function Test-WtwCursorAppRunning {
    [CmdletBinding()]
    param()

    try {
        return [bool]@(Get-Process -Name 'Cursor' -ErrorAction SilentlyContinue)
    } catch {
        # Some macOS pwsh/.NET runtime combinations fail while materializing
        # Process objects because System.Diagnostics.FileVersionInfo is absent.
        # Fall back to pgrep so we still avoid editing Cursor state while its
        # desktop process is running.
        Write-Verbose "Cursor process probe via Get-Process failed: $($_.Exception.Message)"
        if ($IsMacOS -or $IsLinux) {
            $pgrep = Get-Command pgrep -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($pgrep) {
                try {
                    & $pgrep.Source -x Cursor 2>$null | Out-Null
                    return $LASTEXITCODE -eq 0
                } catch {
                    Write-Verbose "Cursor process probe via pgrep failed: $($_.Exception.Message)"
                }
            }
        }

        return $false
    }
}

function Stop-WtwCursorProcess {
    [CmdletBinding()]
    param([int] $TimeoutSeconds = 10)

    $processes = @(Get-Process -Name 'Cursor' -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) { return $true }

    foreach ($process in $processes) {
        try { $process.CloseMainWindow() | Out-Null } catch { }
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-WtwCursorAppRunning)) { return $true }
        Start-Sleep -Milliseconds 250
    }

    foreach ($process in @(Get-Process -Name 'Cursor' -ErrorAction SilentlyContinue)) {
        try { $process.Kill($true) } catch { try { $process.Kill() } catch { } }
    }

    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-WtwCursorAppRunning)) { return $true }
        Start-Sleep -Milliseconds 250
    }

    return -not (Test-WtwCursorAppRunning)
}

function Resolve-WtwCursorStateConflict {
    [CmdletBinding()]
    param([string] $PrettyName = 'the WTW workspace')

    if (-not (Test-WtwCursorAppRunning)) { return $true }

    Write-Host ''
    Write-Host '  Cursor is running — it can overwrite Agents workspace metadata on exit.' -ForegroundColor Yellow
    Write-Host "  Close Cursor once to migrate the Agents label to '$PrettyName'." -ForegroundColor Yellow
    Write-Host '    [c] Close Cursor yourself, then migrate (I will wait)'
    Write-Host '    [k] Force-close Cursor, then migrate'
    Write-Host '    [s] Skip — open with the existing Agents label'

    $answer = (Read-Host '  Choice [c/k/s]').Trim().ToLowerInvariant()
    if (-not $answer) { $answer = 'c' }

    switch ($answer) {
        'c' {
            Write-Host '  Waiting for Cursor to close (Ctrl+C to abort)...' -ForegroundColor Cyan
            while (Test-WtwCursorAppRunning) { Start-Sleep -Milliseconds 500 }
            Write-Host '  Cursor closed.' -ForegroundColor Green
            return $true
        }
        'k' {
            Write-Host '  Force-closing Cursor...' -ForegroundColor Cyan
            if (-not (Stop-WtwCursorProcess)) {
                Write-Host '  Could not stop Cursor — skipping Agents label migration.' -ForegroundColor Red
                return $false
            }
            Write-Host '  Cursor stopped.' -ForegroundColor Green
            return $true
        }
        default {
            Write-Host '  Skipped Cursor Agents label migration.' -ForegroundColor DarkGray
            return $false
        }
    }
}

function Get-WtwCursorPrettyWorkspacePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [Parameter(Mandatory)][string] $PrettyName,
        [string] $RepoName
    )

    $workspaceDirectory = Split-Path ([System.IO.Path]::GetFullPath($WorkspacePath)) -Parent
    $stem = ConvertTo-WtwWorkspaceFileStem -Name $PrettyName
    $candidate = Join-Path $workspaceDirectory "$stem.code-workspace"
    if (-not (Test-Path $candidate) -or
        [System.IO.Path]::GetFullPath($candidate) -eq [System.IO.Path]::GetFullPath($WorkspacePath)) {
        return $candidate
    }

    if ($RepoName) {
        $stem = ConvertTo-WtwWorkspaceFileStem -Name "$RepoName — $PrettyName"
        return (Join-Path $workspaceDirectory "$stem.code-workspace")
    }

    return $candidate
}

function Move-WtwCursorWorkspaceForAgents {
    <#
    .SYNOPSIS
        Rename a saved workspace while preserving Cursor Agents project history.
    .DESCRIPTION
        Cursor's Agents window renders a saved workspace from the
        .code-workspace filename. Renaming it changes Cursor's MD5 workspace id,
        so this migrates the workspace file, workspaceStorage directory, recent
        paths, workspace metadata, and local Agents project identifiers together.
        Cursor must be closed by the caller.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [Parameter(Mandatory)][string] $PrettyName,
        [string] $RepoName,
        [string] $DataHome = (Get-WtwCursorDataHome)
    )

    $oldPath = [System.IO.Path]::GetFullPath($WorkspacePath)
    $newPath = Get-WtwCursorPrettyWorkspacePath -WorkspacePath $oldPath -PrettyName $PrettyName -RepoName $RepoName
    $newPath = [System.IO.Path]::GetFullPath($newPath)
    if ($oldPath -eq $newPath) { return $oldPath }

    if (Test-Path $newPath) {
        Write-Host "  Cursor: Agents label target already exists; keeping '$oldPath'." -ForegroundColor Yellow
        return $oldPath
    }
    if (Test-WtwCursorAppRunning) {
        Write-Host '  Cursor: close Cursor before migrating an existing Agents workspace label.' -ForegroundColor Yellow
        return $oldPath
    }

    $sqlite = Get-WtwSqliteCommand
    $statePath = Get-WtwCursorGlobalStatePath -DataHome $DataHome
    if ((Test-Path $statePath) -and -not $sqlite) {
        Write-Host '  Cursor: sqlite3 is required to preserve Agents history; label migration skipped.' -ForegroundColor Yellow
        return $oldPath
    }

    $oldId = ConvertTo-WtwCursorWorkspaceId -WorkspacePath $oldPath
    $newId = ConvertTo-WtwCursorWorkspaceId -WorkspacePath $newPath
    $oldUri = ConvertTo-WtwFileUri -Path $oldPath
    $newUri = ConvertTo-WtwFileUri -Path $newPath
    $workspaceStorageRoot = Join-Path $DataHome 'User/workspaceStorage'
    $oldStoragePath = Join-Path $workspaceStorageRoot $oldId
    $newStoragePath = Join-Path $workspaceStorageRoot $newId
    if ((Test-Path $oldStoragePath) -and (Test-Path $newStoragePath)) {
        Write-Host "  Cursor: workspace state already exists for '$newPath'; migration skipped." -ForegroundColor Yellow
        return $oldPath
    }

    $backupRoot = Join-Path $DataHome ('User/wtw-backups/{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $oldId)
    New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
    Copy-Item -LiteralPath $oldPath -Destination (Join-Path $backupRoot (Split-Path $oldPath -Leaf)) -Force

    $keysToMigrate = @(
        'history.recentlyOpenedPathsList',
        'glass.localAgentProjects.v1',
        'workspaceMetadata.entries',
        '__$__targetStorageMarker'
    )
    $stateValues = [ordered]@{}
    if (Test-Path $statePath) {
        foreach ($key in $keysToMigrate) {
            $stateValues[$key] = Read-WtwCursorStateValue -StatePath $statePath -Key $key
        }
        [ordered]@{
            oldPath = $oldPath
            newPath = $newPath
            oldId   = $oldId
            newId   = $newId
            values  = [ordered]@{
                'history.recentlyOpenedPathsList' = $stateValues['history.recentlyOpenedPathsList']
                'glass.localAgentProjects.v1' = $stateValues['glass.localAgentProjects.v1']
                'workspaceMetadata.entries' = $stateValues['workspaceMetadata.entries']
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $backupRoot 'cursor-state-rows.json') -Encoding utf8
    }

    $storageJsonPath = Join-Path $DataHome 'User/globalStorage/storage.json'
    if (Test-Path $storageJsonPath) {
        Copy-Item -LiteralPath $storageJsonPath -Destination (Join-Path $backupRoot 'storage.json') -Force
    }

    $movedWorkspace = $false
    $movedStorage = $false
    try {
        Move-Item -LiteralPath $oldPath -Destination $newPath
        $movedWorkspace = $true

        if (Test-Path $oldStoragePath) {
            Move-Item -LiteralPath $oldStoragePath -Destination $newStoragePath
            $movedStorage = $true
            $workspaceJsonPath = Join-Path $newStoragePath 'workspace.json'
            if (Test-Path $workspaceJsonPath) {
                $workspaceJson = Get-Content -LiteralPath $workspaceJsonPath -Raw
                $workspaceJson.Replace($oldUri, $newUri).Replace($oldPath, $newPath) |
                    Set-Content -LiteralPath $workspaceJsonPath -Encoding utf8
            }
        }

        if (Test-Path $storageJsonPath) {
            $storageJson = Get-Content -LiteralPath $storageJsonPath -Raw
            $storageJson.Replace($oldUri, $newUri).Replace($oldPath, $newPath).Replace($oldId, $newId) |
                Set-Content -LiteralPath $storageJsonPath -Encoding utf8
        }

        if (Test-Path $statePath) {
            $statements = [System.Collections.Generic.List[string]]::new()
            $statements.Add('begin immediate;')
            foreach ($key in $keysToMigrate) {
                $value = $stateValues[$key]
                if ([string]::IsNullOrEmpty($value)) { continue }
                $updatedValue = $value.Replace($oldUri, $newUri).Replace($oldPath, $newPath).Replace($oldId, $newId)
                $updateStatement = 'update ItemTable set value = {0} where key = {1};' -f @(
                    (ConvertTo-WtwSqliteLiteral $updatedValue),
                    (ConvertTo-WtwSqliteLiteral $key)
                )
                $statements.Add($updateStatement)
            }
            $oldIdLiteral = ConvertTo-WtwSqliteLiteral $oldId
            $newIdLiteral = ConvertTo-WtwSqliteLiteral $newId
            $statements.Add(@"
insert or replace into ItemTable (key, value)
select replace(key, $oldIdLiteral, $newIdLiteral), value
from ItemTable
where instr(key, $oldIdLiteral) > 0
  and (key like 'agentData.cacheStorage.%' or key like 'cursor/glass.%');
"@)
            $statements.Add(@"
delete from ItemTable
where instr(key, $oldIdLiteral) > 0
  and (key like 'agentData.cacheStorage.%' or key like 'cursor/glass.%');
"@)
            $statements.Add('commit;')
            & $sqlite $statePath ($statements -join [Environment]::NewLine) 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw 'Cursor state database migration failed.'
            }
        }
    } catch {
        if (Test-Path (Join-Path $backupRoot 'storage.json')) {
            Copy-Item -LiteralPath (Join-Path $backupRoot 'storage.json') -Destination $storageJsonPath -Force
        }
        if ($movedStorage -and (Test-Path $newStoragePath) -and -not (Test-Path $oldStoragePath)) {
            $workspaceJsonPath = Join-Path $newStoragePath 'workspace.json'
            if (Test-Path $workspaceJsonPath) {
                $workspaceJson = Get-Content -LiteralPath $workspaceJsonPath -Raw
                $workspaceJson.Replace($newUri, $oldUri).Replace($newPath, $oldPath) |
                    Set-Content -LiteralPath $workspaceJsonPath -Encoding utf8
            }
            Move-Item -LiteralPath $newStoragePath -Destination $oldStoragePath
        }
        if ($movedWorkspace -and (Test-Path $newPath) -and -not (Test-Path $oldPath)) {
            Move-Item -LiteralPath $newPath -Destination $oldPath
        }
        Write-Host "  Cursor: Agents label migration failed: $($_.Exception.Message)" -ForegroundColor Red
        return $oldPath
    }

    Write-Host "  Cursor: Agents workspace label '$PrettyName'" -ForegroundColor Green
    Write-Host "  Cursor: migration backup $backupRoot" -ForegroundColor DarkGray
    return $newPath
}

function Read-WtwCursorRecentlyOpenedState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $StatePath)

    if (-not (Test-Path $StatePath)) {
        return [PSCustomObject]@{ entries = @() }
    }

    $sqlite = Get-WtwSqliteCommand
    if (-not $sqlite) {
        Write-Host '  Cursor: sqlite3 not found - skipping recent workspace registration.' -ForegroundColor DarkGray
        return $null
    }

    $sql = "select value from ItemTable where key = 'history.recentlyOpenedPathsList' limit 1;"
    $value = & $sqlite $StatePath $sql 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host '  Cursor: could not read state.vscdb - skipping recent workspace registration.' -ForegroundColor Yellow
        return $null
    }

    $raw = ($value -join [Environment]::NewLine)
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [PSCustomObject]@{ entries = @() }
    }

    try {
        return $raw | ConvertFrom-Json
    } catch {
        Write-Host '  Cursor: could not parse recently-opened state - skipping update.' -ForegroundColor Yellow
        return $null
    }
}

function Save-WtwCursorRecentlyOpenedState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSObject] $State,
        [Parameter(Mandatory)][string] $StatePath
    )

    $sqlite = Get-WtwSqliteCommand
    if (-not $sqlite) {
        Write-Host '  Cursor: sqlite3 not found - skipping recent workspace registration.' -ForegroundColor DarkGray
        return $false
    }

    $stateDir = Split-Path $StatePath -Parent
    if (-not (Test-Path $stateDir)) {
        New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
    }

    $json = $State | ConvertTo-Json -Depth 80 -Compress
    $jsonLiteral = ConvertTo-WtwSqliteLiteral $json
    $sql = @(
        'create table if not exists ItemTable (key TEXT, value BLOB);',
        "delete from ItemTable where key = 'history.recentlyOpenedPathsList';",
        "insert into ItemTable (key, value) values ('history.recentlyOpenedPathsList', $jsonLiteral);"
    ) -join [Environment]::NewLine

    & $sqlite $StatePath $sql 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host '  Cursor: could not save state.vscdb - skipping recent workspace registration.' -ForegroundColor Yellow
        return $false
    }

    return $true
}

function Set-WtwCursorRecentWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [string] $StatePath = (Get-WtwCursorGlobalStatePath)
    )

    $fullWorkspacePath = [System.IO.Path]::GetFullPath($WorkspacePath)
    $workspaceUri = ConvertTo-WtwFileUri -Path $fullWorkspacePath
    $workspaceId = ConvertTo-WtwCursorWorkspaceId -WorkspacePath $fullWorkspacePath

    $state = Read-WtwCursorRecentlyOpenedState -StatePath $StatePath
    if (-not $state) { return $false }

    $entry = [PSCustomObject]@{
        workspace = [PSCustomObject]@{
            id         = $workspaceId
            configPath = $workspaceUri
        }
    }

    $entries = @()
    if ((Get-WtwPropertyNames -Object $state) -contains 'entries' -and $state.entries) {
        $entries = @($state.entries)
    }

    $entries = @($entries | Where-Object {
        $existingWorkspace = if ((Get-WtwPropertyNames -Object $_) -contains 'workspace') { $_.workspace } else { $null }
        $existingConfigPath = if ($existingWorkspace -and (Get-WtwPropertyNames -Object $existingWorkspace) -contains 'configPath') { $existingWorkspace.configPath } else { $null }
        $existingConfigPath -ne $workspaceUri
    })
    $state | Add-Member -NotePropertyName 'entries' -NotePropertyValue (@($entry) + $entries) -Force

    return (Save-WtwCursorRecentlyOpenedState -State $state -StatePath $StatePath)
}

function Remove-WtwCursorRecentWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [string] $StatePath = (Get-WtwCursorGlobalStatePath)
    )

    if (-not (Test-Path $StatePath)) { return $false }

    $workspaceUri = ConvertTo-WtwFileUri -Path $WorkspacePath
    $state = Read-WtwCursorRecentlyOpenedState -StatePath $StatePath
    if (-not $state) { return $false }

    $entries = @()
    if ((Get-WtwPropertyNames -Object $state) -contains 'entries' -and $state.entries) {
        $entries = @($state.entries)
    }
    $filtered = @($entries | Where-Object {
        $existingWorkspace = if ((Get-WtwPropertyNames -Object $_) -contains 'workspace') { $_.workspace } else { $null }
        $existingConfigPath = if ($existingWorkspace -and (Get-WtwPropertyNames -Object $existingWorkspace) -contains 'configPath') { $existingWorkspace.configPath } else { $null }
        $existingConfigPath -ne $workspaceUri
    })

    if ($filtered.Count -eq $entries.Count) { return $false }

    $state | Add-Member -NotePropertyName 'entries' -NotePropertyValue $filtered -Force
    return (Save-WtwCursorRecentlyOpenedState -State $state -StatePath $StatePath)
}

function Register-WtwCursorProject {
    <#
    .SYNOPSIS
        Register a generated code-workspace in Cursor's recent workspace list.
    .DESCRIPTION
        Cursor stores recent workspaces in VS Code's SQLite-backed
        history.recentlyOpenedPathsList. The schema does not expose a stable
        custom label field; Cursor renders the workspace from the
        .code-workspace path/name. Colors are carried by the workspace file's
        workbench.colorCustomizations / wtw.color settings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [string] $ProjectPath,
        [string] $PrettyName,
        [string] $Color,
        [string] $StatePath
    )

    if (-not (Test-Path $WorkspacePath)) { return $null }
    if (-not (Test-WtwCursorPresent)) {
        Write-Host '  Cursor: not installed/present - skipping recent workspace registration.' -ForegroundColor DarkGray
        return $null
    }

    $splat = @{ WorkspacePath = $WorkspacePath }
    if ($StatePath) { $splat.StatePath = $StatePath }
    if (Set-WtwCursorRecentWorkspace @splat) {
        $label = if ($PrettyName) { " '$PrettyName'" } else { '' }
        $colorLabel = if ($Color) { " ($Color)" } else { '' }
        Write-Host "  Cursor: registered recent workspace${label}${colorLabel}" -ForegroundColor Green
        return [System.IO.Path]::GetFullPath($WorkspacePath)
    }

    return $null
}

function Unregister-WtwCursorProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [string] $StatePath
    )

    $splat = @{ WorkspacePath = $WorkspacePath }
    if ($StatePath) { $splat.StatePath = $StatePath }
    if (Remove-WtwCursorRecentWorkspace @splat) {
        Write-Host '  Cursor: removed recent workspace metadata.' -ForegroundColor Green
    }
}
