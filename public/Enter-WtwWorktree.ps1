function Enter-WtwWorktree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name
    )

    $registry = Get-WtwRegistry

    # Resolution order:
    # 1. Exact alias match -> go to main repo
    # 2. "alias-task" format -> go to worktree
    # 3. Just task name -> search all repos for unique match

    $targetPath = $null
    $sessionScript = $null

    # 1. Check if it's a repo alias (go to main)
    foreach ($repoName in $registry.repos.PSObject.Properties.Name) {
        $repo = $registry.repos.$repoName
        if ((Test-WtwAliasMatch $repo $Name) -or $repoName -eq $Name) {
            $targetPath = $repo.mainPath
            $sessionScript = $repo.sessionScript
            break
        }
    }

    # 2. Check "alias-task" format
    if (-not $targetPath -and $Name -match '^(.+?)-(.+)$') {
        $aliasOrName = $Matches[1]
        $taskName = $Matches[2]
        foreach ($repoName in $registry.repos.PSObject.Properties.Name) {
            $repo = $registry.repos.$repoName
            if (((Test-WtwAliasMatch $repo $aliasOrName) -or $repoName -eq $aliasOrName) -and
                $repo.worktrees -and $repo.worktrees.PSObject.Properties.Name -contains $taskName) {
                $wt = $repo.worktrees.$taskName
                $targetPath = $wt.path
                $sessionScript = $repo.sessionScript
                break
            }
        }
    }

    # 3. Search all repos for task name
    if (-not $targetPath) {
        $found = @()
        foreach ($repoName in $registry.repos.PSObject.Properties.Name) {
            $repo = $registry.repos.$repoName
            if ($repo.worktrees -and $repo.worktrees.PSObject.Properties.Name -contains $Name) {
                $found += @{ repo = $repo; task = $Name }
            }
        }
        if ($found.Count -eq 1) {
            $targetPath = $found[0].repo.worktrees.($found[0].task).path
            $sessionScript = $found[0].repo.sessionScript
        } elseif ($found.Count -gt 1) {
            Write-Error "Ambiguous task name '$Name'. Found in multiple repos. Use 'alias-task' format."
            return
        }
    }

    if (-not $targetPath) {
        Write-Error "Could not resolve '$Name'. Run 'wtw list' to see available targets."
        return
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
