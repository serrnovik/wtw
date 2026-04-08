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
