function New-WtwWorktree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Task,

        [string] $Branch,
        [string] $Repo,
        [switch] $Open,
        [switch] $NoBranch
    )

    $repoName, $repoEntry = Resolve-WtwRepo -RepoAlias $Repo
    if (-not $repoName) { return }

    if ($repoEntry.worktrees.PSObject.Properties.Name -contains $Task) {
        Write-Error "Worktree '$Task' already exists for $repoName. Use 'wtw go $Task' or 'wtw remove $Task' first."
        return
    }

    $worktreePath = Join-Path $repoEntry.worktreeParent "${repoName}_${Task}"

    if (Test-Path $worktreePath) {
        Write-Error "Path already exists: $worktreePath"
        return
    }

    if (-not $Branch) { $Branch = $Task }

    # Create git worktree
    Write-Host "  Creating worktree..." -ForegroundColor Cyan
    $mainRepo = $repoEntry.mainPath

    if ($NoBranch) {
        $result = git -C $mainRepo worktree add $worktreePath $Branch 2>&1
    } else {
        $result = git -C $mainRepo worktree add -b $Branch $worktreePath 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Error "git worktree add failed: $result"
        return
    }

    Write-Host "  Worktree: $worktreePath" -ForegroundColor Green
    Write-Host "  Branch:   $Branch" -ForegroundColor Green

    # Pick color
    $color = New-WtwColor -RepoName $repoName -TaskName $Task
    Write-Host "  Color:    $color" -ForegroundColor Green

    # Generate workspace file
    $wsFile = $null
    $config = Get-WtwConfig
    # Use template source (.template file) if available, fall back to templateWorkspace
    $templatePath = if ($repoEntry.template -and (Test-Path $repoEntry.template)) { $repoEntry.template }
                    elseif ($repoEntry.templateWorkspace -and (Test-Path $repoEntry.templateWorkspace)) { $repoEntry.templateWorkspace }
                    else { $null }

    if ($config -and $templatePath) {
        $wsDir = $config.workspacesDir.Replace('~', $HOME)
        $wsDir = [System.IO.Path]::GetFullPath($wsDir)
        $wsFile = Join-Path $wsDir "${repoName}_${Task}.code-workspace"

        New-WtwWorkspaceFile `
            -RepoName $repoName `
            -Name "${repoName}_${Task}" `
            -CodeFolderPath $worktreePath `
            -TemplatePath $templatePath `
            -OutputPath $wsFile `
            -Color $color `
            -Branch $Branch `
            -WorktreePath $worktreePath `
            -Managed | Out-Null

        Write-Host "  Workspace: $wsFile" -ForegroundColor Green
    } else {
        Write-Host '  Workspace: (no template configured, skipped)' -ForegroundColor Yellow
    }

    # Register in registry
    $registry = Get-WtwRegistry
    $wtEntry = [PSCustomObject]@{
        path      = $worktreePath
        branch    = $Branch
        workspace = $wsFile
        color     = $color
        created   = (Get-Date -Format 'o')
    }
    $registry.repos.$repoName.worktrees | Add-Member -NotePropertyName $Task -NotePropertyValue $wtEntry -Force
    Save-WtwRegistry $registry

    # Superset integration disabled — Superset manages its own worktrees via subtrees
    # if (Test-WtwSupersetInstalled) {
    #     Sync-WtwSupersetProject -RepoPath $worktreePath -Name "${repoName}_${Task}" -Color $color
    # }

    if ($Open) {
        Open-WtwWorkspace -Name $Task -Repo $repoName
    }

    Write-Host ''
    Write-Host "  Done! Use 'wtw go $Task' to switch." -ForegroundColor Green
}
