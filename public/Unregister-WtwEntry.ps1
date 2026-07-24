function Unregister-WtwEntry {
    <#
    .SYNOPSIS
        Remove a repo or worktree from the wtw registry only (no git or disk changes).
    .DESCRIPTION
        Drops the registry entry and associated Peacock color assignments. Does not run
        git worktree remove, delete checkout directories, or remove .code-workspace files.

        Symmetry with registration:
        - Main repo: registered with ``wtw init`` → remove with ``wtw unregister <repo>``.
        - Worktree listing: added with ``wtw add ... --repo ... --task`` → drop listing with
          ``wtw unregister <task>`` (or alias-task) without touching the clone.

        For full teardown of a worktree (git remove, delete folder, workspace file), use
        ``wtw remove``.
    .PARAMETER Name
        Repo alias, main repo path, worktree name, or alias-task (same resolution as go/remove).
    .PARAMETER Repo
        When the name is ambiguous, pin the parent repo (registry key or alias).
    .PARAMETER Force
        Skip the confirmation prompt.
    .EXAMPLE
        wtw unregister sn3
        Stop tracking the snowmain3 main repo and all its registered worktrees in wtw.
    .EXAMPLE
        wtw unregister sn3-brain-search-review --force
        Remove only that worktree from the registry (orphan / MISSING path cleanup).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,

        [string] $Repo,
        [switch] $Force
    )

    $target = Resolve-WtwTarget $Name
    if (-not $target) { return }

    if ($Repo) {
        $registryCheck = Get-WtwRegistry
        $resolvedRepoName = $null
        foreach ($rn in (Get-WtwPropertyNames -Object $registryCheck.repos)) {
            $r = $registryCheck.repos.$rn
            if ($rn -eq $Repo -or (Test-WtwAliasMatch $r $Repo)) {
                $resolvedRepoName = $rn
                break
            }
        }
        if (-not $resolvedRepoName) {
            Write-Error "Unknown repo '$Repo' (not in registry)."
            return
        }
        if ($target.RepoName -ne $resolvedRepoName) {
            Write-Error "Target '$Name' resolves to repo '$($target.RepoName)', not '$resolvedRepoName' (--repo mismatch)."
            return
        }
    }

    $repoName  = $target.RepoName
    $repoEntry = $target.RepoEntry

    if ($target.TaskName) {
        $task = $target.TaskName
        Write-Host ''
        Write-Host "  Unregister worktree from wtw: $repoName / $task" -ForegroundColor Yellow
        Write-Host "  Path: $($target.WorktreeEntry.path)"
        Write-Host "  (Git checkout and files are not modified.)" -ForegroundColor DarkGray

        if (-not $Force) {
            $confirm = Read-Host '  Confirm unregister from wtw only? [y/N]'
            if ($confirm -notin @('y', 'Y', 'yes')) {
                Write-Host '  Cancelled.' -ForegroundColor DarkGray
                return
            }
        }

        $registry = Get-WtwRegistry
        $worktrees = $registry.repos.$repoName.worktrees
        if (-not $worktrees -or ((Get-WtwPropertyNames -Object $worktrees) -notcontains $task)) {
            Write-Warning "Worktree '$task' not present in registry (nothing to do)."
            return
        }

        $newWorktrees = [PSCustomObject]@{}
        foreach ($prop in $worktrees.PSObject.Properties) {
            if ($prop.Name -ne $task) {
                $newWorktrees | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
            }
        }
        $registry.repos.$repoName.worktrees = $newWorktrees
        Save-WtwRegistry $registry

        $colors = Get-WtwColors
        $colorKey = "$repoName/$task"
        if ((Get-WtwPropertyNames -Object $colors.assignments) -contains $colorKey) {
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
        Write-Host "  Unregistered worktree '$task' from $repoName (registry only)." -ForegroundColor Green
        return
    }

    # Whole repo
    Write-Host ''
    Write-Host "  Unregister repo from wtw: $repoName" -ForegroundColor Yellow
    Write-Host "  Main path: $($repoEntry.mainPath)"
    if ($repoEntry.worktrees -and (Get-WtwPropertyNames -Object $repoEntry.worktrees).Count -gt 0) {
        $wtNames = (Get-WtwPropertyNames -Object $repoEntry.worktrees) -join ', '
        Write-Host "  Also drops registry entries for worktrees: $wtNames"
    }
    Write-Host "  (Git, checkouts, and workspace files are not modified.)" -ForegroundColor DarkGray

    if (-not $Force) {
        $confirm = Read-Host '  Confirm unregister entire repo from wtw? [y/N]'
        if ($confirm -notin @('y', 'Y', 'yes')) {
            Write-Host '  Cancelled.' -ForegroundColor DarkGray
            return
        }
    }

    $registry = Get-WtwRegistry
    if ((Get-WtwPropertyNames -Object $registry.repos) -notcontains $repoName) {
        Write-Warning "Repo '$repoName' not in registry (nothing to do)."
        return
    }

    $newRepos = [PSCustomObject]@{}
    foreach ($prop in $registry.repos.PSObject.Properties) {
        if ($prop.Name -ne $repoName) {
            $newRepos | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
        }
    }
    $registry.repos = $newRepos
    Save-WtwRegistry $registry

    $colors = Get-WtwColors
    $newAssignments = [PSCustomObject]@{}
    foreach ($prop in $colors.assignments.PSObject.Properties) {
        $n = $prop.Name
        if ($n -ne "${repoName}/main" -and $n -notlike "${repoName}/*") {
            $newAssignments | Add-Member -NotePropertyName $n -NotePropertyValue $prop.Value
        }
    }
    $colors.assignments = $newAssignments
    Save-WtwColors $colors

    Write-Host ''
    Write-Host "  Unregistered repo '$repoName' from wtw (registry only)." -ForegroundColor Green
}
