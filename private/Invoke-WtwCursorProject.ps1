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

    $uri = ConvertTo-WtwFileUri -Path $WorkspacePath
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($uri)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    $hex = -join ($hash | ForEach-Object { $_.ToString('x2') })
    return $hex.Substring(0, 32)
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
        workbench.colorCustomizations / peacock.color settings.
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
