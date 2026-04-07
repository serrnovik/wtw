function Resolve-WtwSyncTargetFromFile {
    <#
    .SYNOPSIS
        Build a sync target object from a workspace file path, resolving color source.
    #>
    param(
        [string] $TargetPath,
        [string] $ColorSource,
        [string] $TemplateOverride
    )

    $wsContent = Read-JsoncFile $TargetPath
    if (-not $wsContent) { return $null }

    $rn = $wsContent.settings.'wtw.repo'
    $tn = $wsContent.settings.'wtw.task'

    $colors = Get-WtwColors
    $taskKey = if ($tn -and $rn) {
        $reg = Get-WtwRegistry
        $repoEntry = if ($rn -and $reg.repos.PSObject.Properties.Name -contains $rn) { $reg.repos.$rn } else { $null }
        # wtw.task may store the workspace name (e.g. "repo_task") rather than the
        # registry worktree key ("task"). Try exact match first, then strip repo prefix.
        $wtName = $tn
        if ($repoEntry -and $repoEntry.worktrees -and -not ($repoEntry.worktrees.PSObject.Properties.Name -contains $wtName)) {
            $prefix = "${rn}_"
            if ($tn.StartsWith($prefix)) { $wtName = $tn.Substring($prefix.Length) }
        }
        if ($repoEntry -and $repoEntry.worktrees -and $repoEntry.worktrees.PSObject.Properties.Name -contains $wtName) { "$rn/$wtName" } else { "$rn/main" }
    } else { $null }
    $authColor = if ($taskKey -and $colors.assignments.PSObject.Properties.Name -contains $taskKey) { $colors.assignments.$taskKey } else { $null }
    $workspacePeacockColor = $wsContent.settings.'peacock.color'

    # Determine color source preference
    $canPrompt = [Environment]::UserInteractive
    try { $canPrompt = $canPrompt -and [bool]$Host.UI.RawUI } catch { $canPrompt = $false }

    $preferWorkspace = $false
    if ($ColorSource -eq 'Workspace') {
        $preferWorkspace = $true
    } elseif ($ColorSource -eq 'Json') {
        $preferWorkspace = $false
    } elseif ($canPrompt) {
        Write-Host ''
        Write-Host '  Which color should drive this sync?' -ForegroundColor Cyan
        Write-Host '    [J] colors.json assignment (default)' -ForegroundColor Gray
        Write-Host '    [W] peacock.color in the workspace file' -ForegroundColor Gray
        $reply = Read-Host '  Press J or W (Enter = J)'
        $preferWorkspace = (($reply ?? '').Trim()) -match '^[Ww]'
    }

    $resolvedColor = if ($preferWorkspace) { $workspacePeacockColor ?? $authColor } else { $authColor ?? $workspacePeacockColor }

    return [PSCustomObject]@{
        wsFile         = $TargetPath
        repoName       = $rn
        wsName         = $tn ?? [System.IO.Path]::GetFileNameWithoutExtension($TargetPath)
        codeFolderPath = $wsContent.settings.'wtw.worktreePath' ?? ($wsContent.folders[0].path)
        color          = $resolvedColor
        branch         = $wsContent.settings.'wtw.branch'
        worktreePath   = $wsContent.settings.'wtw.worktreePath'
        templatePath   = $(if ($TemplateOverride) { $TemplateOverride } else { $wsContent.settings.'wtw.templateSource' })
        isManaged      = [bool]$wsContent.settings.'wtw.managed'
    }
}

function Resolve-WtwWorkspaceFile {
    <#
    .SYNOPSIS
        Resolve a name/alias/path to a workspace file path.
    #>
    param(
        [string] $Target,
        [string] $WsDir
    )

    # Try as a file path first
    $path = if ([System.IO.Path]::IsPathRooted($Target)) { $Target } else { Join-Path $WsDir $Target }
    if (Test-Path $path) { return $path }

    # Resolve as repo/worktree name
    $resolved = Resolve-WtwTarget $Target
    if (-not $resolved) { return $null }
    $wsFile = if ($resolved.WorktreeEntry) { $resolved.WorktreeEntry.workspace } else { $resolved.RepoEntry.templateWorkspace }
    if ($wsFile -and (Test-Path $wsFile)) { return $wsFile }

    Write-Error "No workspace file found for '$Target'."
    return $null
}

function Sync-WtwWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Target,

        [switch] $All,
        [switch] $DryRun,
        [switch] $Force,
        [string] $Template,  # override template source for this sync
        [string] $Repo,      # limit --all to a specific repo

        # Single-file sync only: prefer colors.json (default) vs workspace peacock.color. Omit to prompt when interactive.
        [ValidateSet('Json', 'Workspace', IgnoreCase = $true)]
        [string] $ColorSource
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

    # Collect sync targets
    $syncTargets = @()

    if ($Target) {
        $targetPath = Resolve-WtwWorkspaceFile $Target $wsDir
        if (-not $targetPath) { return }
        $item = Resolve-WtwSyncTargetFromFile $targetPath $ColorSource $templateOverride
        if ($item) { $syncTargets += $item }

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
        # No target, no --all: detect from cwd
        $detected = Resolve-WtwCurrentTarget
        if (-not $detected) {
            Write-Host ''
            Write-Host '  Usage:' -ForegroundColor Yellow
            Write-Host '    wtw sync [name] [--dry-run]               Sync current or named workspace'
            Write-Host '    wtw sync --all [--dry-run]                Sync all managed workspaces'
            Write-Host '    wtw sync --all --repo sn3                 Sync one repo only'
            Write-Host '    wtw sync --all --template <path>          Sync all with a new template'
            Write-Host '    wtw sync <name> --color-source json       Skip prompt; use colors.json first'
            Write-Host '    wtw sync <name> --color-source workspace  Skip prompt; use workspace peacock first'
            Write-Host ''
            return
        }
        Write-Host "  Detected: $detected" -ForegroundColor DarkGray
        $targetPath = Resolve-WtwWorkspaceFile $detected $wsDir
        if (-not $targetPath) { return }
        $item = Resolve-WtwSyncTargetFromFile $targetPath $ColorSource $templateOverride
        if ($item) { $syncTargets += $item }
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
