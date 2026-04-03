function Sync-WtwWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Target,

        [switch] $All,
        [switch] $DryRun,
        [switch] $Force
    )

    $config = Get-WtwConfig
    if (-not $config) {
        Write-Error 'wtw not initialized. Run "wtw init" first.'
        return
    }

    $registry = Get-WtwRegistry
    $wsDir = $config.workspacesDir.Replace('~', $HOME)
    $wsDir = [System.IO.Path]::GetFullPath($wsDir)

    # Collect workspace files to sync
    $syncTargets = @()

    if ($Target) {
        # Specific file
        $targetPath = if ([System.IO.Path]::IsPathRooted($Target)) {
            $Target
        } else {
            Join-Path $wsDir $Target
        }
        if (-not (Test-Path $targetPath)) {
            Write-Error "Workspace file not found: $targetPath"
            return
        }
        $syncTargets += $targetPath
    } elseif ($All) {
        # All managed workspaces from registry
        foreach ($repoName in $registry.repos.PSObject.Properties.Name) {
            $repo = $registry.repos.$repoName
            if (-not $repo.worktrees) { continue }
            foreach ($taskName in $repo.worktrees.PSObject.Properties.Name) {
                $wt = $repo.worktrees.$taskName
                if ($wt.workspace -and (Test-Path $wt.workspace)) {
                    $syncTargets += $wt.workspace
                }
            }
        }
    } else {
        Write-Host '  Usage: wtw sync <workspace-file> or wtw sync --all' -ForegroundColor Yellow
        return
    }

    if ($syncTargets.Count -eq 0) {
        Write-Host '  No managed workspaces to sync.' -ForegroundColor DarkGray
        return
    }

    Write-Host ''
    Write-Host "  Syncing $($syncTargets.Count) workspace(s)..." -ForegroundColor Cyan
    $synced = 0

    foreach ($wsFile in $syncTargets) {
        $wsContent = Read-JsoncFile $wsFile
        if (-not $wsContent) {
            Write-Host "  SKIP: Cannot read $wsFile" -ForegroundColor Yellow
            continue
        }

        # Check if managed
        $isManaged = $wsContent.settings.'wtw.managed'
        if (-not $isManaged -and -not $Force) {
            Write-Host "  SKIP: $wsFile (not wtw-managed, use --force to override)" -ForegroundColor Yellow
            continue
        }

        # Read instance-specific values to preserve
        $repoName = $wsContent.settings.'wtw.repo'
        $taskName = $wsContent.settings.'wtw.task'
        $branch = $wsContent.settings.'wtw.branch'
        $worktreePath = $wsContent.settings.'wtw.worktreePath'
        $templateSource = $wsContent.settings.'wtw.templateSource'
        $color = $wsContent.settings.'peacock.color'

        # Resolve template
        if (-not $templateSource -or -not (Test-Path $templateSource)) {
            # Try from registry
            if ($repoName -and $registry.repos.PSObject.Properties.Name -contains $repoName) {
                $templateSource = $registry.repos.$repoName.templateWorkspace
            }
        }

        if (-not $templateSource -or -not (Test-Path $templateSource)) {
            Write-Host "  SKIP: $wsFile (template not found)" -ForegroundColor Yellow
            continue
        }

        # Determine code folder path (preserve from current workspace)
        $codeFolderPath = if ($worktreePath) { $worktreePath } elseif ($wsContent.folders -and $wsContent.folders.Count -gt 0) { $wsContent.folders[0].path } else { $null }

        if (-not $codeFolderPath) {
            Write-Host "  SKIP: $wsFile (cannot determine code folder)" -ForegroundColor Yellow
            continue
        }

        $wsName = if ($taskName -and $repoName) { "${repoName}_${taskName}" } else { [System.IO.Path]::GetFileNameWithoutExtension($wsFile) }

        if ($DryRun) {
            Write-Host "  WOULD SYNC: $wsFile (template: $(Split-Path $templateSource -Leaf))" -ForegroundColor DarkGray
            continue
        }

        # Regenerate from template, preserving instance values
        New-WtwWorkspaceFile `
            -RepoName ($repoName ?? 'unknown') `
            -Name $wsName `
            -CodeFolderPath $codeFolderPath `
            -TemplatePath $templateSource `
            -OutputPath $wsFile `
            -Color $color `
            -Branch $branch `
            -WorktreePath $worktreePath `
            -Managed | Out-Null

        $synced++
        Write-Host "  SYNCED: $(Split-Path $wsFile -Leaf)" -ForegroundColor Green
    }

    Write-Host ''
    if ($DryRun) {
        Write-Host "  (dry-run: $($syncTargets.Count) workspace(s) would be synced)" -ForegroundColor DarkGray
    } else {
        Write-Host "  Synced $synced workspace(s)." -ForegroundColor Green
    }
    Write-Host ''
}
