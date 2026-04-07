function Sync-WtwWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Target,

        [switch] $All,
        [switch] $DryRun,
        [switch] $Force,
        [string] $Template,  # override template source for this sync
        [string] $Repo       # limit --all to a specific repo
    )

    $config = Get-WtwConfig
    if (-not $config) {
        Write-Error 'wtw not initialized. Run "wtw init" first.'
        return
    }

    $registry = Get-WtwRegistry
    $wsDir = $config.workspacesDir.Replace('~', $HOME)
    $wsDir = [System.IO.Path]::GetFullPath($wsDir)

    # Resolve template override
    $templateOverride = $null
    if ($Template) {
        $templateOverride = [System.IO.Path]::GetFullPath($Template)
        if (-not (Test-Path $templateOverride)) {
            Write-Error "Template not found: $templateOverride"
            return
        }
    }

    # Collect sync targets: { wsFile, repoName, codeFolderPath, color, branch, worktreePath, wsName, templatePath }
    $syncTargets = @()

    if ($Target) {
        # Specific file
        $targetPath = if ([System.IO.Path]::IsPathRooted($Target)) { $Target } else { Join-Path $wsDir $Target }
        if (-not (Test-Path $targetPath)) {
            Write-Error "Workspace file not found: $targetPath"
            return
        }
        $wsContent = Read-JsoncFile $targetPath
        if ($wsContent) {
            $rn = $wsContent.settings.'wtw.repo'
            $tn = $wsContent.settings.'wtw.task'

            # Prefer colors.json (authoritative) over workspace file (may be stale)
            $colors = Get-WtwColors
            $taskKey = if ($tn -and $rn) {
                # Check if this is a worktree task or main
                $reg = Get-WtwRegistry
                $repoEntry = if ($rn -and $reg.repos.PSObject.Properties.Name -contains $rn) { $reg.repos.$rn } else { $null }
                if ($repoEntry -and $repoEntry.worktrees -and $repoEntry.worktrees.PSObject.Properties.Name -contains $tn) { "$rn/$tn" } else { "$rn/main" }
            } else { $null }
            $authColor = if ($taskKey -and $colors.assignments.PSObject.Properties.Name -contains $taskKey) { $colors.assignments.$taskKey } else { $null }

            $syncTargets += [PSCustomObject]@{
                wsFile         = $targetPath
                repoName       = $rn
                wsName         = $tn ?? [System.IO.Path]::GetFileNameWithoutExtension($targetPath)
                codeFolderPath = $wsContent.settings.'wtw.worktreePath' ?? ($wsContent.folders[0].path)
                color          = $authColor ?? $wsContent.settings.'peacock.color'
                branch         = $wsContent.settings.'wtw.branch'
                worktreePath   = $wsContent.settings.'wtw.worktreePath'
                templatePath   = $templateOverride ?? $wsContent.settings.'wtw.templateSource'
                isManaged      = [bool]$wsContent.settings.'wtw.managed'
            }
        }
    } elseif ($All) {
        # All registered repos — main workspace + worktree workspaces
        foreach ($repoName in $registry.repos.PSObject.Properties.Name) {
            $repoEntry = $registry.repos.$repoName
            if ($Repo -and -not (Test-WtwAliasMatch $repoEntry $Repo) -and $repoName -ne $Repo) { continue }

            $tpl = $templateOverride ?? $repoEntry.template ?? $repoEntry.templateWorkspace
            $repoDir = Split-Path $repoEntry.mainPath -Leaf

            # Main workspace
            if ($repoEntry.templateWorkspace -and (Test-Path $repoEntry.templateWorkspace)) {
                $colors = Get-WtwColors
                $mainColor = $colors.assignments."$repoName/main"
                $syncTargets += [PSCustomObject]@{
                    wsFile         = $repoEntry.templateWorkspace
                    repoName       = $repoName
                    wsName         = $repoDir
                    codeFolderPath = $repoEntry.mainPath
                    color          = $mainColor
                    branch         = $null
                    worktreePath   = $null
                    templatePath   = $tpl
                    isManaged      = $true
                }
            }

            # Worktree workspaces
            if ($repoEntry.worktrees) {
                foreach ($taskName in $repoEntry.worktrees.PSObject.Properties.Name) {
                    $wt = $repoEntry.worktrees.$taskName
                    if ($wt.workspace -and (Test-Path $wt.workspace)) {
                        $syncTargets += [PSCustomObject]@{
                            wsFile         = $wt.workspace
                            repoName       = $repoName
                            wsName         = "${repoName}_${taskName}"
                            codeFolderPath = $wt.path
                            color          = $wt.color
                            branch         = $wt.branch
                            worktreePath   = $wt.path
                            templatePath   = $tpl
                            isManaged      = $true
                        }
                    }
                }
            }
        }
    } else {
        Write-Host ''
        Write-Host '  Usage:' -ForegroundColor Yellow
        Write-Host '    wtw sync --all [--dry-run]              Sync all managed workspaces'
        Write-Host '    wtw sync --all --repo sn3               Sync one repo only'
        Write-Host '    wtw sync --all --template <path>        Sync all with a new template'
        Write-Host '    wtw sync <workspace-file> [--dry-run]   Sync a specific file'
        Write-Host ''
        return
    }

    if ($syncTargets.Count -eq 0) {
        Write-Host '  No managed workspaces to sync.' -ForegroundColor DarkGray
        return
    }

    Write-Host ''
    Write-Host "  Syncing $($syncTargets.Count) workspace(s)..." -ForegroundColor Cyan
    $synced = 0

    foreach ($item in $syncTargets) {
        if (-not $item.isManaged -and -not $Force) {
            Write-Host "  SKIP: $($item.wsFile) (not wtw-managed, use --force)" -ForegroundColor Yellow
            continue
        }

        $tpl = $item.templatePath
        if (-not $tpl -or -not (Test-Path $tpl)) {
            Write-Host "  SKIP: $(Split-Path $item.wsFile -Leaf) (template not found)" -ForegroundColor Yellow
            continue
        }

        if (-not $item.codeFolderPath) {
            Write-Host "  SKIP: $(Split-Path $item.wsFile -Leaf) (cannot determine code folder)" -ForegroundColor Yellow
            continue
        }

        if ($DryRun) {
            Write-Host "  WOULD SYNC: $(Split-Path $item.wsFile -Leaf) (template: $(Split-Path $tpl -Leaf))" -ForegroundColor DarkGray
            continue
        }

        New-WtwWorkspaceFile `
            -RepoName ($item.repoName ?? 'unknown') `
            -Name $item.wsName `
            -CodeFolderPath $item.codeFolderPath `
            -TemplatePath $tpl `
            -OutputPath $item.wsFile `
            -Color $item.color `
            -Branch $item.branch `
            -WorktreePath $item.worktreePath `
            -Managed | Out-Null

        $synced++
        Write-Host "  SYNCED: $(Split-Path $item.wsFile -Leaf)" -ForegroundColor Green
    }

    Write-Host ''
    if ($DryRun) {
        Write-Host "  (dry-run: $($syncTargets.Count) workspace(s) would be synced)" -ForegroundColor DarkGray
    } else {
        Write-Host "  Synced $synced workspace(s)." -ForegroundColor Green
    }
    Write-Host ''
}
