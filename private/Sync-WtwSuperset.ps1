$script:SupersetDbPath = Join-Path $HOME '.superset' 'local.db'

function Test-WtwSupersetInstalled {
    return (Test-Path $script:SupersetDbPath)
}

function Sync-WtwSupersetProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath,

        [Parameter(Mandatory)]
        [string] $Name,

        [string] $Color = 'default',

        [string] $DefaultBranch = 'main'
    )

    if (-not (Test-WtwSupersetInstalled)) { return }

    # Check if project already exists
    $existing = sqlite3 $script:SupersetDbPath "SELECT id FROM projects WHERE main_repo_path = '$RepoPath';" 2>$null
    if ($existing) {
        # Update color and name
        sqlite3 $script:SupersetDbPath "UPDATE projects SET color = '$Color', name = '$Name' WHERE main_repo_path = '$RepoPath';" 2>$null
        Write-Host "  Superset: updated project '$Name'" -ForegroundColor DarkGray
    } else {
        # Insert new project
        $id = [guid]::NewGuid().ToString()
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        # Find next tab_order
        $maxOrder = sqlite3 $script:SupersetDbPath "SELECT COALESCE(MAX(tab_order), -1) FROM projects;" 2>$null
        $tabOrder = [int]$maxOrder + 1

        sqlite3 $script:SupersetDbPath "INSERT INTO projects (id, main_repo_path, name, color, tab_order, last_opened_at, created_at, default_branch) VALUES ('$id', '$RepoPath', '$Name', '$Color', $tabOrder, $now, $now, '$DefaultBranch');" 2>$null
        Write-Host "  Superset: created project '$Name'" -ForegroundColor DarkGray
    }
}

function Remove-WtwSupersetProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    if (-not (Test-WtwSupersetInstalled)) { return }

    $existing = sqlite3 $script:SupersetDbPath "SELECT name FROM projects WHERE main_repo_path = '$RepoPath';" 2>$null
    if ($existing) {
        # CASCADE will clean up workspaces
        sqlite3 $script:SupersetDbPath "DELETE FROM projects WHERE main_repo_path = '$RepoPath';" 2>$null
        Write-Host "  Superset: removed project '$existing'" -ForegroundColor DarkGray
    }
}

function Get-WtwSupersetColorName {
    # Map hex colors to Superset's named color palette
    param([string] $Hex)

    $colorMap = @{
        '#ef4444' = '#ef4444'; '#f97316' = '#f97316'; '#eab308' = '#eab308'
        '#22c55e' = '#22c55e'; '#14b8a6' = '#14b8a6'; '#3b82f6' = '#3b82f6'
        '#8b5cf6' = '#8b5cf6'; '#a855f7' = '#a855f7'; '#ec4899' = '#ec4899'
    }

    # Superset uses raw hex, so just pass through
    return $Hex
}
