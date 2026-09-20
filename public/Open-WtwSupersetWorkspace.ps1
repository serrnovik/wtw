function Open-WtwSupersetWorkspace {
    <#
    .SYNOPSIS
        Find a Superset workspace matching a wtw target and open the Superset app.
    .DESCRIPTION
        Looks up the Superset project for the target's repo, then matches a local
        Superset workspace by branch or task name. Opens the Superset desktop app
        on a hit. On miss, prints helpful next-step commands.

        Falls back gracefully when the Superset CLI is missing, the user is not
        logged in, or no project/workspace matches.
    .PARAMETER Target
        Resolved wtw target object (output of Resolve-WtwTarget).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Target
    )

    if (-not (Get-Command superset -ErrorAction SilentlyContinue)) {
        Write-WtwHost '  Superset CLI not installed.' -ForegroundColor Yellow
        Write-WtwHost '    Install: brew install superset-sh/tap/superset' -ForegroundColor DarkGray
        return
    }

    # Resolve branch + task for matching.
    # Always ask git for the live branch — the registry's stored branch can be stale
    # (worktree dir keeps its original name even after `git switch` / branch rename).
    if ($Target.WorktreeEntry) {
        $workDir = $Target.WorktreeEntry.path
        $task    = $Target.TaskName
    } else {
        $workDir = $Target.RepoEntry.mainPath
        $task    = $null
    }
    $branch = & git -C $workDir rev-parse --abbrev-ref HEAD 2>$null
    if (-not $branch -and $Target.WorktreeEntry) {
        $branch = $Target.WorktreeEntry.branch  # fallback if git query failed
    }
    if (-not $task) { $task = $branch }
    $repoName = $Target.RepoName

    # Fetch projects
    $projectsJson = & superset projects list --json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-WtwHost '  Superset: not logged in or service unreachable.' -ForegroundColor Yellow
        Write-WtwHost '    superset auth login' -ForegroundColor DarkGray
        return
    }
    try {
        $projects = $projectsJson | ConvertFrom-Json
    } catch {
        Write-WtwHost '  Superset: could not parse projects list.' -ForegroundColor Yellow
        return
    }

    $project = $projects | Where-Object {
        [string]::Equals($_.slug, $repoName, [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($_.name, $repoName, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1

    if (-not $project) {
        Write-WtwHost "  Superset: no project matches repo '$repoName'." -ForegroundColor Yellow
        Write-WtwHost '    Create one in the Superset desktop app (no CLI verb yet).' -ForegroundColor DarkGray
        if ($projects.Count -gt 0) {
            Write-WtwHost '    Existing projects:' -ForegroundColor DarkGray
            foreach ($p in $projects) {
                Write-WtwHost "      - $($p.name) (slug: $($p.slug))" -ForegroundColor DarkGray
            }
        }
        return
    }

    # Fetch local workspaces
    $wsJson = & superset workspaces list --local --json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-WtwHost '  Superset: workspaces list failed.' -ForegroundColor Yellow
        Write-WtwHost "    $wsJson" -ForegroundColor DarkGray
        return
    }
    try {
        $workspaces = $wsJson | ConvertFrom-Json
    } catch {
        Write-WtwHost '  Superset: could not parse workspaces list.' -ForegroundColor Yellow
        return
    }

    $projectWorkspaces = @($workspaces | Where-Object { $_.projectId -eq $project.id })

    $ws = $projectWorkspaces | Where-Object {
        [string]::Equals($_.branch, $branch, [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($_.name, $task, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1

    if ($ws) {
        Write-WtwHost "  Superset: found workspace '$($ws.name)' (branch: $($ws.branch))" -ForegroundColor Green
        Write-WtwHost "    project: $($project.name)" -ForegroundColor DarkGray
        Write-WtwHost "    id:      $($ws.id)" -ForegroundColor DarkGray
        $supersetPath = Join-Path $HOME ".superset/worktrees/$($project.slug)/$($ws.name)"
        if (Test-Path $supersetPath) {
            Write-WtwHost "    path:    $supersetPath" -ForegroundColor DarkGray
        }
        Repair-WtwSupersetProjectPath -ProjectId $project.id -ExpectedRepoPath $Target.RepoEntry.mainPath
        Write-WtwHost '  Opening Superset workspace...' -ForegroundColor Cyan
        Write-WtwHost "    $ superset ws open $($ws.id)" -ForegroundColor DarkGray
        $openResult = & superset ws open $ws.id 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-WtwHost "  Superset: ws open failed: $openResult" -ForegroundColor Yellow
            Write-WtwHost '  Falling back to launching the app...' -ForegroundColor DarkGray
            & open -a Superset
        }
        return
    }

    # Not found — print helpful guidance
    Write-WtwHost "  Superset: no workspace for branch '$branch' in project '$($project.name)'." -ForegroundColor Yellow
    if ($projectWorkspaces.Count -gt 0) {
        Write-WtwHost "    Existing workspaces in '$($project.name)':" -ForegroundColor DarkGray
        foreach ($w in $projectWorkspaces) {
            Write-WtwHost "      - $($w.name)  (branch: $($w.branch))" -ForegroundColor DarkGray
        }
    }
    Write-WtwHost ''
    Write-WtwHost '  To create one in Superset (uses its own worktree on a different branch):' -ForegroundColor DarkGray
    Write-WtwHost "    superset workspaces create --local --project $($project.id) --name <name> --branch <new-branch> --base-branch $branch" -ForegroundColor DarkGray
}
