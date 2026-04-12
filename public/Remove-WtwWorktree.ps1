function Remove-WtwWorktree {
    <#
    .SYNOPSIS
        Remove a worktree, its workspace file, git branch, and recycle its color.
    .DESCRIPTION
        Removes the git worktree directory, deletes the associated workspace file,
        prunes the worktree reference, unregisters it from the registry, and
        recycles the color assignment.
    .PARAMETER Name
        The worktree to remove (task name or alias-task combo).
    .PARAMETER Repo
        Specify the parent repo when the name alone is ambiguous.
    .PARAMETER Force
        Skip the confirmation prompt.
    .EXAMPLE
        wtw remove auth --force
        Remove the "auth" worktree without asking for confirmation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,

        [string] $Repo,
        [switch] $Force
    )

    # Use unified resolution: supports aliases, "alias-task" format, and bare task names
    $target = Resolve-WtwTarget $Name
    if (-not $target) { return }

    if (-not $target.TaskName) {
        Write-Error "'$Name' resolves to main repo '$($target.RepoName)', not a worktree. Specify a worktree name."
        return
    }

    $repoName  = $target.RepoName
    $repoEntry = $target.RepoEntry
    $Task      = $target.TaskName
    $wt        = $target.WorktreeEntry

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

    Write-Host ''
    Write-Host "  Removed '$Task' from $repoName." -ForegroundColor Green
}
