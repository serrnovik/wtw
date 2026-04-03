function Remove-WtwWorktree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Task,

        [string] $Repo,
        [switch] $Force
    )

    $repoName, $repoEntry = Resolve-WtwRepo -RepoAlias $Repo
    if (-not $repoName) { return }

    if ($repoEntry.worktrees.PSObject.Properties.Name -notcontains $Task) {
        Write-Error "Worktree '$Task' not found for $repoName."
        return
    }

    $wt = $repoEntry.worktrees.$Task

    Write-Host ''
    Write-Host "  Removing worktree: $Task" -ForegroundColor Yellow
    Write-Host "  Path:     $($wt.path)"
    Write-Host "  Branch:   $($wt.branch)"
    Write-Host "  Workspace: $($wt.workspace)"

    if (-not $Force) {
        $confirm = Read-Host '  Confirm removal? [y/N]'
        if ($confirm -notin @('y', 'Y', 'yes')) {
            Write-Host '  Cancelled.' -ForegroundColor DarkGray
            return
        }
    }

    # Remove git worktree
    if (Test-Path $wt.path) {
        Write-Host '  Removing git worktree...' -ForegroundColor Cyan
        $result = git -C $repoEntry.mainPath worktree remove $wt.path --force 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "git worktree remove failed: $result"
            Write-Host '  Falling back to manual removal...' -ForegroundColor Yellow
            Remove-Item -Path $wt.path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Remove workspace file
    if ($wt.workspace -and (Test-Path $wt.workspace)) {
        Remove-Item -Path $wt.workspace -Force
        Write-Host "  Removed workspace: $($wt.workspace)" -ForegroundColor Green
    }

    # Prune
    git -C $repoEntry.mainPath worktree prune 2>$null

    # Remove from registry
    $registry = Get-WtwRegistry
    $worktrees = $registry.repos.$repoName.worktrees
    $newWorktrees = [PSCustomObject]@{}
    foreach ($prop in $worktrees.PSObject.Properties) {
        if ($prop.Name -ne $Task) {
            $newWorktrees | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
        }
    }
    $registry.repos.$repoName.worktrees = $newWorktrees
    Save-WtwRegistry $registry

    # Recycle color
    $colors = Get-WtwColors
    $colorKey = "$repoName/$Task"
    if ($colors.assignments.PSObject.Properties.Name -contains $colorKey) {
        $newAssignments = [PSCustomObject]@{}
        foreach ($prop in $colors.assignments.PSObject.Properties) {
            if ($prop.Name -ne $colorKey) {
                $newAssignments | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
            }
        }
        $colors.assignments = $newAssignments
        Save-WtwColors $colors
    }

    # Remove from Superset
    if (Test-WtwSupersetInstalled -and $wt.path) {
        Remove-WtwSupersetProject -RepoPath $wt.path
    }

    Write-Host ''
    Write-Host "  Removed '$Task' from $repoName." -ForegroundColor Green
}
