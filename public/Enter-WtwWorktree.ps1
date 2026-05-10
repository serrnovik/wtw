function Enter-WtwWorktree {
    <#
    .SYNOPSIS
        Switch to a worktree directory and run session initialization.
    .DESCRIPTION
        Resolves the target by repo alias, task name, or alias-task combo,
        changes to its directory, and runs the repo session script if available.
    .PARAMETER Name
        Repo alias, task name, or alias-task combo (e.g. "app-auth").
    .EXAMPLE
        wtw go auth
        Switch to the "auth" worktree directory and initialize the session.
    .NOTES
        Side effects:
        - Changes the current location (Set-Location) to the worktree directory.
        - Sets WTW_* and DEV_WORKTREE_* environment variables for tooling integration.
        - May run a repo session script (e.g. start-repository-session.ps1) if configured.
        - Sets terminal tab color and title via escape sequences when no session script handles it.
    #>
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
        $resolvedLabel = if ($target.TaskName) { "$($target.RepoName) / $($target.TaskName)" } else { $target.RepoName }
        Write-Host ''
        Write-Host '  ✗  Worktree path not found' -ForegroundColor Red
        Write-Host ''
        Write-Host "  Resolved:  $resolvedLabel" -ForegroundColor DarkGray
        Write-Host "  Path:      $targetPath" -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  The worktree is registered but its directory no longer exists.' -ForegroundColor Yellow
        Write-Host "  To recreate:    wtw create $Name" -ForegroundColor Cyan
        Write-Host "  To unregister:  wtw remove $Name" -ForegroundColor Cyan
        Write-Host ''
        return
    }

    # Resolve the color for this target (for terminal tab coloring)
    $targetColor = if ($target.WorktreeEntry) {
        $target.WorktreeEntry.color
    } else {
        (Get-WtwColors).assignments."$($target.RepoName)/main"
    }
    $targetTitle = if ($target.TaskName) {
        "$($target.RepoName)/$($target.TaskName)"
    } else {
        $target.RepoName
    }

    # Set worktree environment variables (WTW_*, DEV_WORKTREE_*)
    Set-WtwWorktreeEnv -TaskName $target.TaskName -RepoEntry $repo

    # Use Set-GitRepo if available (from user profile), otherwise direct approach
    if (Get-Command 'Set-GitRepo' -ErrorAction SilentlyContinue) {
        $toolName = if ($sessionScript) { $sessionScript } else { 'start-repository-session.ps1' }
        Set-GitRepo -gitRoot $targetPath -toolName $toolName
    } else {
        Set-Location $targetPath
        $scriptRan = $false
        if ($sessionScript) {
            $scriptPath = Join-Path $targetPath $sessionScript
            if (Test-Path $scriptPath) {
                & $scriptPath
                $scriptRan = $true
            }
        }
        # If no session script handled the terminal, set color and title ourselves
        $prNumber = $null
        if (-not $scriptRan) {
            $prNumber = Get-WtwCurrentPrNumber
            $titleWithPr = if ($prNumber) { "$targetTitle #$prNumber" } else { $targetTitle }
            Set-WtwTerminalColor -Color $targetColor -Title $titleWithPr
        }
        Write-Host "  Switched to: $targetPath" -ForegroundColor Green
        if ($prNumber) {
            Write-Host "  PR 🔗: #$prNumber" -ForegroundColor DarkCyan
        }
    }
}
