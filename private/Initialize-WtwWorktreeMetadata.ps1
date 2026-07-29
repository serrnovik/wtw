function Initialize-WtwWorktreeMetadata {
    <#
    .SYNOPSIS
        Shared post-worktree setup: color, workspace file, registry, and
        all external registrations (Superset, Codex, cmux, wmux, SourceGit,
        agentctl).
    .DESCRIPTION
        Called by both `wtw create` (after `git worktree add`) and `wtw add`
        (after validating that the worktree path exists on disk and resolves
        to the parent repo). The two callers differ only in how the
        worktree comes to exist; everything that follows is identical and
        lives here.

        Returns a hashtable describing what was registered:
          @{ Success = $true/$false
             Color = '#rrggbb'
             PrettyName = '<emoji name>'
             WorkspaceFile = '<path>' or $null
             SupersetWorkspaceId, CodexProjectPath, CursorWorkspacePath, CmuxCommandKey, WmuxWorkspaceName }
        Caller is responsible for any rollback on Success=$false (typically
        only relevant when `create` just made the worktree and needs to
        unwind on a bad --color).
    .PARAMETER RepoName
        Registry key of the parent repo.
    .PARAMETER RepoEntry
        Registry object for the parent repo (used to read template path,
        config knobs, etc.).
    .PARAMETER Task
        Task name (registry key under the repo).
    .PARAMETER Branch
        Branch checked out in the worktree. Used in the workspace template
        and surfaced in Superset/UI.
    .PARAMETER WorktreePath
        Absolute path to the worktree directory.
    .PARAMETER FolderSuffix
        The directory's `${repoName}_<suffix>` tail. Used as the default
        pretty name.
    .PARAMETER PrettyName
        Optional human-readable display name. Defaults to $FolderSuffix.
        A color-circle emoji is always prepended so downstream UIs render
        the right swatch.
    .PARAMETER Color
        Optional palette/hex/'random' input passed to Resolve-WtwColorInput.
        Defaults to 'random' (max-contrast pick).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoName,
        [Parameter(Mandatory)] [PSCustomObject] $RepoEntry,
        [Parameter(Mandatory)] [string] $Task,
        [Parameter(Mandatory)] [string] $Branch,
        [Parameter(Mandatory)] [string] $WorktreePath,
        [Parameter(Mandatory)] [string] $FolderSuffix,
        [string] $PrettyName,
        [string] $Color
    )

    $result = @{
        Success             = $false
        Color               = $null
        PrettyName          = $null
        WorkspaceFile       = $null
        SupersetWorkspaceId = $null
        CodexProjectPath    = $null
        ClaudeCodeTrustPath = $null
        CursorWorkspacePath = $null
        CmuxCommandKey      = $null
        WmuxWorkspaceName   = $null
    }

    # Pick color: explicit hex/name/random, else default to random max-contrast pick.
    $colorKey = "$RepoName/$Task"
    if ($Color) {
        $resolvedColor = Resolve-WtwColorInput -Color $Color -ExcludeKey $colorKey
        if (-not $resolvedColor) {
            Write-Error "Invalid --color '$Color'. Use 'random', a hex (#rrggbb / rrggbb), or a known color name."
            return $result
        }
    } else {
        $resolvedColor = Resolve-WtwColorInput -Color 'random' -ExcludeKey $colorKey
    }
    $result.Color = $resolvedColor

    # Persist assignment so colors.json and registry stay in sync
    $colorsState = Get-WtwColors
    $colorsState.assignments | Add-Member -NotePropertyName $colorKey -NotePropertyValue $resolvedColor -Force
    Save-WtwColors $colorsState
    Write-Host "  Color:    $resolvedColor" -ForegroundColor Green

    # Pretty name: default to the folder suffix (i.e. path without the `${RepoName}_` prefix);
    # always prepend a color-circle emoji that matches the assigned color so it surfaces in
    # SourceGit/Superset and any other UI that reads `prettyName`.
    if (-not $PrettyName) { $PrettyName = $FolderSuffix }
    $PrettyName = Format-WtwPrettyNameWithCircle -Hex $resolvedColor -Name $PrettyName
    $result.PrettyName = $PrettyName
    Write-Host "  Pretty:   $PrettyName" -ForegroundColor Green

    # Generate workspace file from the repo's template, when one is configured.
    $wsFile = $null
    $config = Get-WtwConfig
    $templatePath = if ($RepoEntry.template -and (Test-Path $RepoEntry.template)) { $RepoEntry.template }
                    elseif ($RepoEntry.templateWorkspace -and (Test-Path $RepoEntry.templateWorkspace)) { $RepoEntry.templateWorkspace }
                    else { $null }

    if (-not $templatePath -and $RepoEntry.mainPath -and (Test-Path $RepoEntry.mainPath)) {
        $templatePath = Resolve-WtwRepoTemplatePath -RepoRoot $RepoEntry.mainPath
    }

    if ($config -and $templatePath) {
        $wsDir = $config.workspacesDir.Replace('~', $HOME)
        $wsDir = [System.IO.Path]::GetFullPath($wsDir)
        # Cursor's Workspaces sidebar renders the .code-workspace file name.
        # New files can therefore use the human label without touching an
        # existing workspace identity or its chat history.
        $workspaceFileStem = ConvertTo-WtwWorkspaceFileStem -Name $PrettyName
        $wsFile = Join-Path $wsDir "${workspaceFileStem}.code-workspace"
        if (Test-Path $wsFile) {
            $workspaceFileStem = ConvertTo-WtwWorkspaceFileStem -Name "$RepoName — $PrettyName"
            $wsFile = Join-Path $wsDir "${workspaceFileStem}.code-workspace"
        }

        New-WtwWorkspaceFile `
            -RepoName $RepoName `
            -Name $PrettyName `
            -CodeFolderPath $WorktreePath `
            -TemplatePath $templatePath `
            -OutputPath $wsFile `
            -TaskName $Task `
            -Color $resolvedColor `
            -Branch $Branch `
            -WorktreePath $WorktreePath `
            -Managed | Out-Null

        Write-Host "  Workspace: $wsFile" -ForegroundColor Green
    } else {
        Write-Host '  Workspace: (no template configured, skipped)' -ForegroundColor Yellow
    }
    $result.WorkspaceFile = $wsFile

    # Register/overwrite the registry entry. Add-Member -Force lets this safely
    # replace a barebones entry that `wtw add` may have written earlier.
    $registry = Get-WtwRegistry
    $wtEntry = [PSCustomObject]@{
        path                = $WorktreePath
        branch              = $Branch
        workspace           = $wsFile
        color               = $resolvedColor
        created             = (Get-Date -Format 'o')
        prettyName          = $PrettyName
        supersetWorkspaceId = $null
        codexProjectPath    = $null
        claudeCodeTrustPath = $null
        cursorWorkspacePath = $null
        cmuxCommandKey      = $null
        wmuxWorkspaceName   = $null
    }
    $registry.repos.$RepoName.worktrees | Add-Member -NotePropertyName $Task -NotePropertyValue $wtEntry -Force
    Save-WtwRegistry $registry

    # Create Superset workspace (no-op when CLI absent or project not found).
    $supersetWsId = New-WtwSupersetWorkspace -RepoName $RepoName -Branch $Branch -PrettyName $PrettyName -MainRepoPath $registry.repos.$RepoName.mainPath
    if ($supersetWsId) {
        $registry.repos.$RepoName.worktrees.$Task.supersetWorkspaceId = $supersetWsId
        Save-WtwRegistry $registry
        $result.SupersetWorkspaceId = $supersetWsId
    }

    # Register Codex Desktop project metadata (no-op when Codex is absent).
    $codexProjectPath = Register-WtwCodexProject -ProjectPath $WorktreePath -PrettyName $PrettyName
    if ($codexProjectPath) {
        $registry.repos.$RepoName.worktrees.$Task.codexProjectPath = $codexProjectPath
        Save-WtwRegistry $registry
        $result.CodexProjectPath = $codexProjectPath
    }

    # Pre-accept Claude Code's workspace-trust prompt so `wtw claudecode` opens
    # straight into the new worktree (no-op when ~/.claude.json is absent).
    $claudeTrustPath = Register-WtwClaudeCodeProject -ProjectPath $WorktreePath
    if ($claudeTrustPath) {
        $registry.repos.$RepoName.worktrees.$Task.claudeCodeTrustPath = $claudeTrustPath
        Save-WtwRegistry $registry
        $result.ClaudeCodeTrustPath = $claudeTrustPath
    }

    # Register Cursor recent-workspace metadata for the generated workspace
    # file. Cursor displays workspace names from the .code-workspace path, and
    # the file already carries the per-worktree color settings.
    if ($wsFile) {
        $cursorWorkspacePath = Register-WtwCursorProject -WorkspacePath $wsFile -ProjectPath $WorktreePath -PrettyName $PrettyName -Color $resolvedColor
        if ($cursorWorkspacePath) {
            $registry.repos.$RepoName.worktrees.$Task.cursorWorkspacePath = $cursorWorkspacePath
            Save-WtwRegistry $registry
            $result.CursorWorkspacePath = $cursorWorkspacePath
        }
    }

    # Register cmux Command Palette workspace metadata (no-op when cmux is absent).
    $cmuxCommandKey = Register-WtwCmuxProject -ProjectPath $WorktreePath -PrettyName $PrettyName -Color $resolvedColor -RepoName $RepoName -TaskName $Task
    if ($cmuxCommandKey) {
        $registry.repos.$RepoName.worktrees.$Task.cmuxCommandKey = $cmuxCommandKey
        Save-WtwRegistry $registry
        $result.CmuxCommandKey = $cmuxCommandKey
    }

    # Register wmux live workspace when the Windows wmux CLI is installed and
    # reachable. wmux has no SourceGit-style static repository registry today.
    $wmuxWorkspaceName = Register-WtwWmuxProject -ProjectPath $WorktreePath -PrettyName $PrettyName -RepoName $RepoName -TaskName $Task
    if ($wmuxWorkspaceName) {
        $registry.repos.$RepoName.worktrees.$Task.wmuxWorkspaceName = $wmuxWorkspaceName
        Save-WtwRegistry $registry
        $result.WmuxWorkspaceName = $wmuxWorkspaceName
    }

    # Register in SourceGit's managed repository list (no-op when app absent).
    Add-WtwSourceGitRepository -Path $WorktreePath -Name $PrettyName -Hex $resolvedColor

    # Attach the user's local AI-agent overlay when the optional personal
    # `agentctl` helper is installed. Best-effort: must not block setup.
    Invoke-WtwAgentCtlAttach -WorktreePath $WorktreePath -RepoName $RepoName -RepoEntry $RepoEntry -Config $config | Out-Null

    $result.Success = $true
    return $result
}
