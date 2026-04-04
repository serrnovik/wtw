function Enter-WtwWorktree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name
    )

    $target = Resolve-WtwTarget $Name
    if (-not $target) { return }

    $repo = $target.RepoEntry
    $sessionScript = $repo.sessionScript

    if ($target.WorktreeEntry) {
        $targetPath = $target.WorktreeEntry.path
    } else {
        $targetPath = $repo.mainPath
    }

    if (-not (Test-Path $targetPath)) {
        Write-Error "Path does not exist: $targetPath"
        return
    }

    # Use Set-GitRepo if available (from user profile), otherwise direct approach
    if (Get-Command 'Set-GitRepo' -ErrorAction SilentlyContinue) {
        $toolName = if ($sessionScript) { $sessionScript } else { 'start-repository-session.ps1' }
        Set-GitRepo -gitRoot $targetPath -toolName $toolName
    } else {
        Set-Location $targetPath
        if ($sessionScript) {
            $scriptPath = Join-Path $targetPath $sessionScript
            if (Test-Path $scriptPath) {
                & $scriptPath
            }
        }
        Write-Host "  Switched to: $targetPath" -ForegroundColor Green
    }
}
