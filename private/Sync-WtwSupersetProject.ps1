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
