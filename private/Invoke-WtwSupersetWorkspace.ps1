function New-WtwSupersetWorkspace {
    <#
    .SYNOPSIS
        Create a Superset workspace for a wtw worktree.
    .DESCRIPTION
        Looks up the Superset project by repo name, then calls superset ws create.
        Returns the workspace ID on success, $null on any failure.
        Silently skips when the Superset CLI is not installed.
    #>
    param(
        [string] $RepoName,
        [string] $Branch,
        [string] $PrettyName
    )

    if (-not (Get-Command superset -ErrorAction SilentlyContinue)) {
        Write-Host '  Superset: CLI not installed — skipping workspace creation.' -ForegroundColor DarkGray
        return $null
    }

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
    Write-Host "  Superset: creating workspace '$wsName'..." -ForegroundColor Cyan

    $wsJson = & superset ws create --local --project $project.id --name $wsName --branch $Branch --json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Superset: workspace creation failed: $wsJson" -ForegroundColor Yellow
        return $null
    }

    $wsId = $null
    try {
        $ws = $wsJson | ConvertFrom-Json
        $wsId = $ws.id
    } catch {
        # Fallback: extract UUID from plain-text output
        $m = [regex]::Match($wsJson, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
        if ($m.Success) { $wsId = $m.Value }
    }

    if ($wsId) {
        Write-Host "  Superset: workspace created (id: $wsId)" -ForegroundColor Green
    } else {
        Write-Host "  Superset: workspace created (id unknown — check 'superset ws list')" -ForegroundColor Yellow
    }
    return $wsId
}

function Remove-WtwSupersetWorkspace {
    <#
    .SYNOPSIS
        Delete a Superset workspace by ID.
    .DESCRIPTION
        Calls superset ws delete. Skips gracefully when the CLI is absent or the
        workspace ID is empty. Reports but does not abort when deletion fails.
    #>
    param([string] $WorkspaceId)

    if (-not $WorkspaceId) { return }

    if (-not (Get-Command superset -ErrorAction SilentlyContinue)) {
        Write-Host "  Superset: CLI not installed — skipping workspace removal (id: $WorkspaceId)." -ForegroundColor DarkGray
        Write-Host '    Remove manually in the Superset desktop app.' -ForegroundColor DarkGray
        return
    }

    Write-Host "  Superset: removing workspace $WorkspaceId..." -ForegroundColor Cyan
    $result = & superset ws delete $WorkspaceId --local 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Superset: workspace removal failed: $result" -ForegroundColor Yellow
    } else {
        Write-Host '  Superset: workspace removed.' -ForegroundColor Green
    }
}
