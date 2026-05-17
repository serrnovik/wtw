function Open-WtwSupersetWorkspace {
    <#
    .SYNOPSIS
        Find a Superset workspace matching a wtw target and open the Superset app.
    .DESCRIPTION
        Looks up the Superset project for the target's repo, then matches a local
        Superset workspace by branch or task name. Opens the Superset desktop app
        on a hit. On miss, prints helpful next-step commands.

        All superset CLI calls run from the main repository root — the CLI
        invokes simple-git on the cwd and errors with "directory does not exist"
        when called from a worktree path or any non-repo dir.

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
        Write-Host '  Superset CLI not installed.' -ForegroundColor Yellow
        Write-Host '    Install: brew install superset-sh/tap/superset' -ForegroundColor DarkGray
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
    $mainRepoPath = $Target.RepoEntry.mainPath

    if (-not $mainRepoPath -or -not (Test-Path $mainRepoPath)) {
        Write-Host "  Superset: main repo path missing ('$mainRepoPath')." -ForegroundColor Yellow
        return
    }

    Push-Location $mainRepoPath
    try {
        # Fetch projects
        $projectsJson = & superset projects list --json 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host '  Superset: not logged in or service unreachable.' -ForegroundColor Yellow
            Write-Host '    superset auth login' -ForegroundColor DarkGray
            return
        }
        try {
            $projects = $projectsJson | ConvertFrom-Json
        } catch {
            Write-Host '  Superset: could not parse projects list.' -ForegroundColor Yellow
            return
        }

        $project = $projects | Where-Object {
            [string]::Equals($_.slug, $repoName, [System.StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($_.name, $repoName, [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1

        if (-not $project) {
            Write-Host "  Superset: no project matches repo '$repoName'." -ForegroundColor Yellow
            Write-Host '    Create one in the Superset desktop app (no CLI verb yet).' -ForegroundColor DarkGray
            if ($projects.Count -gt 0) {
                Write-Host '    Existing projects:' -ForegroundColor DarkGray
                foreach ($p in $projects) {
                    Write-Host "      - $($p.name) (slug: $($p.slug))" -ForegroundColor DarkGray
                }
            }
            return
        }

        # Fetch local workspaces
        $wsJson = & superset workspaces list --local --json 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host '  Superset: workspaces list failed.' -ForegroundColor Yellow
            Write-Host "    $wsJson" -ForegroundColor DarkGray
            return
        }
        try {
            $workspaces = $wsJson | ConvertFrom-Json
        } catch {
            Write-Host '  Superset: could not parse workspaces list.' -ForegroundColor Yellow
            return
        }

        $projectWorkspaces = @($workspaces | Where-Object { $_.projectId -eq $project.id })

        $ws = $projectWorkspaces | Where-Object {
            [string]::Equals($_.branch, $branch, [System.StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($_.name, $task, [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1

        if ($ws) {
            Write-Host "  Superset: found workspace '$($ws.name)' (branch: $($ws.branch))" -ForegroundColor Green
            Write-Host "    project: $($project.name)" -ForegroundColor DarkGray
            Write-Host "    id:      $($ws.id)" -ForegroundColor DarkGray
            $supersetPath = Join-Path $HOME ".superset/worktrees/$($project.slug)/$($ws.name)"
            if (Test-Path $supersetPath) {
                Write-Host "    path:    $supersetPath" -ForegroundColor DarkGray
            }
            Write-Host '  Opening Superset workspace...' -ForegroundColor Cyan
            $openResult = & superset ws open $ws.id 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  Superset: ws open failed: $openResult" -ForegroundColor Yellow
                Write-Host '  Falling back to launching the app...' -ForegroundColor DarkGray
                & open -a Superset
            }
            return
        }

        # Not found — print helpful guidance.
        # The suggested base-branch is the repo's default branch (main/master), NOT
        # the current branch — basing a new workspace off the worktree branch we
        # failed to find is almost never what the user wants.
        $suggestedBase = Get-WtwSupersetDefaultBaseBranch -RepoPath $mainRepoPath
        Write-Host "  Superset: no workspace for branch '$branch' in project '$($project.name)'." -ForegroundColor Yellow
        if ($projectWorkspaces.Count -gt 0) {
            Write-Host "    Existing workspaces in '$($project.name)':" -ForegroundColor DarkGray
            foreach ($w in $projectWorkspaces) {
                Write-Host "      - $($w.name)  (branch: $($w.branch))" -ForegroundColor DarkGray
            }
        }
        Write-Host ''
        Write-Host '  To create one in Superset (run from the main repo root, not a worktree):' -ForegroundColor DarkGray
        # Quote the path so the suggested `cd` survives copy/paste when
        # the repo lives under a directory with spaces.
        Write-Host "    cd `"$mainRepoPath`"" -ForegroundColor DarkGray
        Write-Host "    superset workspaces create --local --project $($project.id) --name <name> --branch <new-branch> --base-branch $suggestedBase" -ForegroundColor DarkGray
    } finally {
        Pop-Location
    }
}
