function New-WtwWorktree {
    <#
    .SYNOPSIS
        Create a new git worktree with workspace and color assignment.
    .DESCRIPTION
        Creates a git worktree for the given task, generates a VS Code workspace
        file from the repo template, assigns a unique color, and registers it
        in the wtw registry.
    .PARAMETER Task
        Branch or task name for the new worktree.
    .PARAMETER Branch
        Override the git branch name (defaults to the task name).
    .PARAMETER Repo
        Target repo alias if not auto-detected from cwd.
    .PARAMETER Open
        Open the workspace in the configured editor after creation.
    .PARAMETER NoBranch
        Attach to an existing branch instead of creating a new one.
    .PARAMETER PrettyName
        Human-readable display name stored in the registry and used as the
        Superset workspace name (e.g. "035 Context Building 🔵").
    .PARAMETER FolderName
        Override the worktree folder suffix (default: $Task).
        Final folder is "${repoName}_${FolderName}". Useful for long branch
        names: --folder p2 → snowmain1_p2.
    .PARAMETER Color
        Color assignment for the new workspace. Accepts:
          - 'random' (default when omitted): max-contrast pick from the palette
          - '#rrggbb' or 'rrggbb': literal hex
          - color name: looked up in the bundled colornames table (case-insensitive,
            spaces/hyphens ignored) — e.g. 'forest green', 'navy', 'sunset orange'.
    .PARAMETER From
        Start-point for the new branch. Any git ref reachable from the main
        repo: a branch name (local or `origin/<name>`), tag, or commit SHA.
        Special value `current` resolves to the branch checked out in the
        terminal's current directory (typically a worktree's branch) — use
        it to stack the new branch on top of in-flight work without having
        to type the long branch name.
        When omitted, git uses the main repo's current HEAD (typically the
        default branch). Ignored when -NoBranch is set (you're attaching
        to an existing branch).
    .PARAMETER GtTrack
        After creating the worktree, run `gt track` inside it to register
        the new branch with the Graphite CLI. When -From is also set, the
        parent is passed explicitly via --parent so the stack edge is
        recorded immediately. Requires `gt` on PATH; fails fast
        otherwise. If `gt track` errors with a stale trunk reference, the
        worktree is left intact and a remediation hint is printed
        (`gt init` + `gt repo sync`).
    .EXAMPLE
        wtw create auth
        Create a worktree and branch named "auth" for the current repo.
    .EXAMPLE
        wtw create "my feature name"
        Normalizes to my_feature_name for branch, folder, and registry key.
    .EXAMPLE
        wtw create 035-context-building-function --name "035 Context Building 🔵"
        Creates the worktree and registers a pretty name used for Superset.
    .EXAMPLE
        wtw create initiative-016-home --from MS-phase-5-swim-polish
        Stack initiative-016-home on top of MS-phase-5-swim-polish so the
        new branch + worktree start from that branch's tip (Graphite-style
        stack base).
    .EXAMPLE
        wtw create initiative-016-home --from current --gt-track
        Same as above but `current` resolves to the cwd's branch, and the
        new branch is also registered with Graphite (`gt branch track
        --parent <resolved-from>`) so `gt submit --stack` opens the PR
        with the right base immediately.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Task,

        [string] $Branch,
        [string] $Repo,
        [string] $PrettyName,
        [string] $FolderName,
        [string] $Color,
        [string] $From,
        [switch] $Open,
        [switch] $NoBranch,
        [switch] $GtTrack
    )

    $rawTask = $Task
    $Task = ConvertTo-WtwBranchSafeName -Name $Task
    if ([string]::IsNullOrWhiteSpace($Task)) {
        Write-Error "Task name is empty or invalid after normalization (input: '$rawTask')."
        return
    }
    if ($rawTask -ne $Task) {
        Write-Host "  Normalized task/branch: $Task" -ForegroundColor DarkCyan
        Write-Host "    (from: $rawTask)" -ForegroundColor DarkGray
    }

    $repoName, $repoEntry = Resolve-WtwRepo -RepoAlias $Repo
    if (-not $repoName) { return }

    if ($repoEntry.worktrees.PSObject.Properties.Name -contains $Task) {
        Write-Error "Worktree '$Task' already exists for $repoName. Use 'wtw go $Task' or 'wtw remove $Task' first."
        return
    }

    # Folder suffix (default: $Task). Normalized so spaces/casing don't sneak into paths.
    $folderSuffix = if ($FolderName) { ConvertTo-WtwBranchSafeName -Name $FolderName } else { $Task }
    # Reject a normalized empty suffix early — otherwise we'd build a path
    # like `${repoName}_` and silently collide with anything that already
    # uses the bare repo prefix.
    if ($FolderName -and [string]::IsNullOrWhiteSpace($folderSuffix)) {
        Write-Error "Folder name is empty or invalid after normalization (input: '$FolderName')."
        return
    }
    if ($FolderName -and $folderSuffix -ne $FolderName) {
        Write-Host "  Normalized folder name: $folderSuffix" -ForegroundColor DarkCyan
        Write-Host "    (from: $FolderName)" -ForegroundColor DarkGray
    }
    $worktreePath = Join-Path $repoEntry.worktreeParent "${repoName}_${folderSuffix}"

    if (Test-Path $worktreePath) {
        Write-Error "Path already exists: $worktreePath"
        return
    }

    if (-not $Branch) { $Branch = $Task }

    # Create git worktree
    Write-Host "  Creating worktree..." -ForegroundColor Cyan
    $mainRepo = $repoEntry.mainPath

    # Resolve -From upfront so we fail fast with a clear message rather
    # than letting `git worktree add` complain mid-flight.
    if ($From) {
        if ($NoBranch) {
            Write-Error "--from is only meaningful when creating a new branch; drop -NoBranch or omit --from."
            return
        }
        # Special value `current` → resolve against the terminal's cwd.
        # Anywhere inside a worktree of this repo returns that worktree's
        # branch; from the main repo dir it returns the main checkout's
        # branch. Detached HEAD is rejected.
        if ($From -eq 'current') {
            $cwdBranch = git -C (Get-Location).Path rev-parse --abbrev-ref HEAD 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Error "--from current: cwd is not inside a git worktree ($cwdBranch)."
                return
            }
            $cwdBranch = "$cwdBranch".Trim()
            if ($cwdBranch -eq 'HEAD') {
                Write-Error "--from current: cwd is on a detached HEAD; check out a branch first or pass an explicit ref."
                return
            }
            Write-Host "  --from current → '$cwdBranch'" -ForegroundColor DarkGray
            $From = $cwdBranch
        }
        $resolved = git -C $mainRepo rev-parse --verify "$From^{commit}" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "--from '$From' is not a valid ref in $repoName : $resolved"
            return
        }
        Write-Host "  Stack base: $From ($($resolved.Substring(0, 12)))" -ForegroundColor Cyan
    }

    # Fail fast if -GtTrack is set but `gt` isn't on PATH — otherwise the
    # worktree gets created and the tracking step silently no-ops.
    if ($GtTrack) {
        if (-not (Get-Command gt -ErrorAction SilentlyContinue)) {
            Write-Error "--gt-track requires the Graphite CLI on PATH (https://graphite.dev/docs/install)."
            return
        }
    }

    if ($NoBranch) {
        $result = git -C $mainRepo worktree add $worktreePath $Branch 2>&1
    } elseif ($From) {
        $result = git -C $mainRepo worktree add -b $Branch $worktreePath $From 2>&1
    } else {
        $result = git -C $mainRepo worktree add -b $Branch $worktreePath 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Error "git worktree add failed: $result"
        return
    }

    Write-Host "  Worktree: $worktreePath" -ForegroundColor Green
    Write-Host "  Branch:   $Branch" -ForegroundColor Green

    # Pick color: explicit hex/name/random, else default to random max-contrast pick.
    $colorKey = "$repoName/$Task"
    if ($Color) {
        $color = Resolve-WtwColorInput -Color $Color -ExcludeKey $colorKey
        if (-not $color) {
            Write-Error "Invalid --color '$Color'. Use 'random', a hex (#rrggbb / rrggbb), or a known color name."
            git -C $mainRepo worktree remove $worktreePath --force 2>$null | Out-Null
            return
        }
    } else {
        $color = Resolve-WtwColorInput -Color 'random' -ExcludeKey $colorKey
    }

    # Persist assignment so colors.json and registry stay in sync
    $colorsState = Get-WtwColors
    $colorsState.assignments | Add-Member -NotePropertyName $colorKey -NotePropertyValue $color -Force
    Save-WtwColors $colorsState

    Write-Host "  Color:    $color" -ForegroundColor Green

    # Pretty name: default to the folder suffix (i.e. path without the `${repoName}_` prefix);
    # always prepend a color-circle emoji that matches the assigned color so it surfaces in
    # SourceGit/Superset and any other UI that reads `prettyName`.
    if (-not $PrettyName) { $PrettyName = $folderSuffix }
    $PrettyName = Format-WtwPrettyNameWithCircle -Hex $color -Name $PrettyName
    Write-Host "  Pretty:   $PrettyName" -ForegroundColor Green

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
        $wsFile = Join-Path $wsDir "${repoName}_${folderSuffix}.code-workspace"

        New-WtwWorkspaceFile `
            -RepoName $repoName `
            -Name "${repoName}_${folderSuffix}" `
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
        path                = $worktreePath
        branch              = $Branch
        workspace           = $wsFile
        color               = $color
        created             = (Get-Date -Format 'o')
        prettyName          = $PrettyName
        supersetWorkspaceId = $null
        codexProjectPath    = $null
    }
    $registry.repos.$repoName.worktrees | Add-Member -NotePropertyName $Task -NotePropertyValue $wtEntry -Force
    Save-WtwRegistry $registry

    # Create Superset workspace (no-op when CLI absent or project not found)
    $supersetWsId = New-WtwSupersetWorkspace -RepoName $repoName -Branch $Branch -PrettyName $PrettyName -MainRepoPath $registry.repos.$repoName.mainPath
    if ($supersetWsId) {
        $registry.repos.$repoName.worktrees.$Task.supersetWorkspaceId = $supersetWsId
        Save-WtwRegistry $registry
    }

    # Register Codex Desktop project metadata (no-op when Codex is absent).
    $codexProjectPath = Register-WtwCodexProject -ProjectPath $worktreePath -PrettyName $PrettyName
    if ($codexProjectPath) {
        $registry.repos.$repoName.worktrees.$Task.codexProjectPath = $codexProjectPath
        Save-WtwRegistry $registry
    }

    # Register in SourceGit's managed repository list (no-op when app absent).
    # Pass the assigned hex so SourceGit's Bookmark gets the nearest of its 7 palette slots.
    Add-WtwSourceGitRepository -Path $worktreePath -Name $PrettyName -Hex $color

    # Attach the user's local AI-agent overlay when the optional personal
    # `agentctl` helper is installed. This is intentionally best-effort:
    # worktree creation must not depend on personal dotfiles.
    Invoke-WtwAgentCtlAttach -WorktreePath $worktreePath -RepoName $repoName -RepoEntry $repoEntry -Config $config | Out-Null

    # Optionally register the new branch with Graphite. Done inside the
    # new worktree (gt operates on the cwd's branch) and passes --parent
    # when -From is set so the stack edge is recorded immediately.
    #
    # Note on command name: `gt branch track` was renamed to `gt track`
    # in current Graphite. The legacy name still works but prints a
    # deprecation warning that drowns the real output. Use the new name.
    if ($GtTrack) {
        Write-Host "  Tracking with Graphite..." -ForegroundColor Cyan
        Push-Location -LiteralPath $worktreePath
        try {
            $gtArgs = @('track')
            if ($From) { $gtArgs += @('--parent', $From) }
            $gtOut = & gt @gtArgs 2>&1
            if ($LASTEXITCODE -eq 0) {
                $parentLabel = if ($From) { " (parent: $From)" } else { '' }
                Write-Host "  Graphite: tracked${parentLabel}" -ForegroundColor Green
            } else {
                Write-Warning "  gt track failed (exit $LASTEXITCODE): $gtOut"
                # The most common cause is a stale/missing trunk
                # configuration — point the user at the fix.
                if ("$gtOut" -match 'bad revision|trunk|init') {
                    Write-Host "    Likely cause: Graphite trunk is unset or stale. From the main repo:" -ForegroundColor DarkGray
                    Write-Host "      gt init             # interactive: pick trunk (usually 'main')" -ForegroundColor DarkGray
                    Write-Host "      gt repo sync        # refresh remote state" -ForegroundColor DarkGray
                    Write-Host "    Then inside ${worktreePath}:" -ForegroundColor DarkGray
                    $reTry = if ($From) { "      gt track --parent $From" } else { '      gt track' }
                    Write-Host $reTry -ForegroundColor DarkGray
                } else {
                    Write-Host "    Worktree is fine — re-run 'gt track' manually inside $worktreePath." -ForegroundColor DarkGray
                }
            }
        } finally {
            Pop-Location
        }
    }

    if ($Open) {
        Open-WtwWorkspace -Name $Task -Repo $repoName
    }

    Write-Host ''
    Write-Host "  Done! Use 'wtw go $Task' to switch." -ForegroundColor Green
}
