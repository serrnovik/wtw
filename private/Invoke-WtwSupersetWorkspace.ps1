function Get-WtwSupersetDefaultBaseBranch {
    <#
    .SYNOPSIS
        Detect the default branch (main/master) of a git repo.
    .DESCRIPTION
        Tries origin/HEAD first (e.g. "refs/remotes/origin/main" → "main").
        Falls back to "main" if the symbolic-ref is missing, then "master" if
        "main" doesn't exist. The result is what wtw passes to `superset ws create
        --base-branch` so the new workspace forks from a real shared branch
        instead of the throwaway worktree branch the user happens to be on.
    #>
    param([string] $RepoPath)

    if (-not $RepoPath -or -not (Test-Path $RepoPath)) { return 'main' }

    $ref = & git -C $RepoPath symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $ref) {
        return ($ref -replace '^origin/', '')
    }

    & git -C $RepoPath rev-parse --verify --quiet refs/heads/main 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return 'main' }

    & git -C $RepoPath rev-parse --verify --quiet refs/heads/master 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return 'master' }

    return 'main'
}

function New-WtwSupersetWorkspace {
    <#
    .SYNOPSIS
        Create a Superset workspace for a wtw worktree.
    .DESCRIPTION
        Looks up the Superset project by repo name, then calls superset ws create
        from the main repository root (the CLI uses simple-git on the cwd and
        fails with "directory does not exist" if invoked from a worktree path).
        Returns the workspace ID on success, $null on any failure.
        Silently skips when the Superset CLI is not installed.
    #>
    param(
        [string] $RepoName,
        [string] $MainRepoPath,
        [string] $Branch,
        [string] $BaseBranch,
        [string] $PrettyName
    )

    if (-not (Get-Command superset -ErrorAction SilentlyContinue)) {
        Write-Host '  Superset: CLI not installed — skipping workspace creation.' -ForegroundColor DarkGray
        return $null
    }

    if (-not $MainRepoPath -or -not (Test-Path $MainRepoPath)) {
        Write-Host "  Superset: main repo path missing or not found ('$MainRepoPath') — skipping workspace creation." -ForegroundColor Yellow
        return $null
    }

    if (-not $BaseBranch) {
        $BaseBranch = Get-WtwSupersetDefaultBaseBranch -RepoPath $MainRepoPath
    }

    Push-Location $MainRepoPath
    try {
        $projectsJson = & superset projects list --json 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host '  Superset: not logged in or unreachable — skipping workspace creation.' -ForegroundColor Yellow
            return $null
        }
        try { $projects = $projectsJson | ConvertFrom-Json } catch {
            Write-Host '  Superset: could not parse projects list.' -ForegroundColor Yellow
            return $null
        }

        $project = $projects | Where-Object {
            [string]::Equals($_.slug, $RepoName, [System.StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($_.name, $RepoName, [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1

        if (-not $project) {
            Write-Host "  Superset: no project matches repo '$RepoName' — skipping workspace creation." -ForegroundColor Yellow
            return $null
        }

        $wsName = if ($PrettyName) { $PrettyName } else { $Branch }
        Write-Host "  Superset: creating workspace '$wsName' (base: $BaseBranch)..." -ForegroundColor Cyan

        $wsJson = & superset ws create --local --project $project.id --name $wsName --branch $Branch --base-branch $BaseBranch --json 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Superset: workspace creation failed: $wsJson" -ForegroundColor Yellow
            # Self-heal hint: this fires when superset's local projects row points at a
            # repoPath that no longer exists (e.g. a deleted worktree). The cure is to
            # re-import the project at the real main repo path.
            if ("$wsJson" -match 'simple-git on a directory that does not exist') {
                Write-Host '    Likely cause: this Superset project was set up against a path that no longer exists.' -ForegroundColor DarkGray
                Write-Host '    Fix by re-importing at the main repo:' -ForegroundColor DarkGray
                Write-Host "      superset projects setup $($project.id) --local --import $MainRepoPath --allow-relocate" -ForegroundColor DarkGray
            }
            return $null
        }

        $wsId = $null
        try {
            $ws = $wsJson | ConvertFrom-Json
            $wsId = $ws.id
        } catch {
            $m = [regex]::Match($wsJson, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
            if ($m.Success) { $wsId = $m.Value }
        }

        if ($wsId) {
            Write-Host "  Superset: workspace created (id: $wsId)" -ForegroundColor Green
        } else {
            Write-Host "  Superset: workspace created (id unknown — check 'superset ws list')" -ForegroundColor Yellow
        }
        return $wsId
    } finally {
        Pop-Location
    }
}

function Remove-WtwSupersetWorkspace {
    <#
    .SYNOPSIS
        Delete a Superset workspace by ID.
    .DESCRIPTION
        Calls superset ws delete from the main repository root. Skips gracefully
        when the CLI is absent or the workspace ID is empty. Reports but does
        not abort when deletion fails.
    #>
    param(
        [string] $WorkspaceId,
        [string] $MainRepoPath
    )

    if (-not $WorkspaceId) { return }

    if (-not (Get-Command superset -ErrorAction SilentlyContinue)) {
        Write-Host "  Superset: CLI not installed — skipping workspace removal (id: $WorkspaceId)." -ForegroundColor DarkGray
        Write-Host '    Remove manually in the Superset desktop app.' -ForegroundColor DarkGray
        return
    }

    $pushed = $false
    if ($MainRepoPath -and (Test-Path $MainRepoPath)) {
        Push-Location $MainRepoPath
        $pushed = $true
    }
    try {
        Write-Host "  Superset: removing workspace $WorkspaceId..." -ForegroundColor Cyan
        $result = & superset ws delete $WorkspaceId --local 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Superset: workspace removal failed: $result" -ForegroundColor Yellow
        } else {
            Write-Host '  Superset: workspace removed.' -ForegroundColor Green
        }
    } finally {
        if ($pushed) { Pop-Location }
    }
}
