function Repair-WtwSupersetProjectPath {
    <#
    .SYNOPSIS
        Detect and self-heal Superset project repoPath drift before opening a workspace.
    .DESCRIPTION
        Superset stores a per-machine repoPath for each project. When wtw deletes the
        worktree that path pointed at, simpleGit() inside Superset blows up before it
        ever looks at the requested workspace, surfacing as "workspace not found" in
        the desktop app.

        This probes by calling `superset projects setup --local --import <expected>`
        without --allow-relocate:
          * exit 0 -> stored repoPath already matches our expected main repo path
          * error  "Project is already set up on this device at <path>"
              - if <path> doesn't exist on disk: drift; auto-fix with --allow-relocate
              - if <path> exists: leave it alone (user may have moved their repo)

        Silently no-ops when the Superset CLI is missing or the user isn't logged in.
        Caller should proceed with `superset ws open` either way.
    .PARAMETER ProjectId
        Superset project UUID.
    .PARAMETER ExpectedRepoPath
        Absolute path to the main repo clone (wtw's RepoEntry.mainPath).
    #>
    param(
        [Parameter(Mandatory)][string] $ProjectId,
        [Parameter(Mandatory)][string] $ExpectedRepoPath
    )

    if (-not (Get-Command superset -ErrorAction SilentlyContinue)) { return }
    if (-not (Test-Path $ExpectedRepoPath)) {
        Write-Host "  Superset: expected main repo path missing on disk: $ExpectedRepoPath" -ForegroundColor Yellow
        return
    }

    $probe = & superset projects setup $ProjectId --local --import $ExpectedRepoPath 2>&1
    if ($LASTEXITCODE -eq 0) { return }  # no drift

    $probeText = ($probe | Out-String)
    $m = [regex]::Match($probeText, 'already set up on this device at\s+(.+?)\.\s')
    if (-not $m.Success) {
        # Unknown failure mode — surface it but don't block ws open
        Write-Host "  Superset: project path probe failed: $($probeText.Trim())" -ForegroundColor Yellow
        return
    }

    $storedPath = $m.Groups[1].Value.Trim()
    if (Test-Path $storedPath) {
        Write-Host "  Superset: project points at $storedPath (exists; leaving as-is)." -ForegroundColor DarkGray
        return
    }

    Write-Host "  Superset: stored repoPath drift detected ($storedPath missing). Self-healing..." -ForegroundColor Yellow
    $heal = & superset projects setup $ProjectId --local --import $ExpectedRepoPath --allow-relocate 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Superset: repoPath relocated to $ExpectedRepoPath." -ForegroundColor Green
    } else {
        Write-Host "  Superset: self-heal failed: $($heal | Out-String).Trim()" -ForegroundColor Yellow
        Write-Host "    Manual fix: superset projects setup $ProjectId --local --import $ExpectedRepoPath --allow-relocate" -ForegroundColor DarkGray
    }
}
