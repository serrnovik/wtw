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
        Branch to use. Without -NoBranch this overrides the *new* branch name
        (defaults to the task name). With -NoBranch this is the *existing* ref
        to adopt: a local branch name (e.g. `my-feature`) or a remote-tracking
        ref (e.g. `origin/my-feature`). Defaults to the task name when omitted.
    .PARAMETER Repo
        Target repo alias if not auto-detected from cwd.
    .PARAMETER Open
        Open the workspace in the configured editor after creation.
    .PARAMETER NoBranch
        Adopt an existing branch instead of creating a new one. The ref is
        taken from -Branch (or the task name when -Branch is omitted). If the
        ref is a remote-tracking branch (e.g. `origin/foo`), a local tracking
        branch is created automatically — the worktree is never detached.
        All the usual color/workspace/registry/cmux/Superset/SourceGit logic
        runs after, identical to the new-branch path.

        In most cases you don't need this switch: when -Branch points at a ref
        that already exists, adoption is inferred automatically. Use -NoBranch
        (or its alias -Adopt) only when you want to adopt with the task name
        as the ref (no explicit -Branch).
    .PARAMETER Adopt
        Friendlier alias for -NoBranch. "Adopt an existing branch." Same
        behavior; pick whichever name reads better at the call site.
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
    .PARAMETER Alias
        Extra typed names for ``wtw go`` (spaces allowed).
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
    .EXAMPLE
        wtw create my-feature --branch my-feature
        Adopt the existing local branch `my-feature`. Adoption is inferred
        automatically because the ref already exists — no --adopt needed.
    .EXAMPLE
        wtw create my-feature --branch origin/my-feature
        Adopt a remote branch. A local tracking branch is created from
        `origin/my-feature` so the worktree is on a real branch, not
        detached HEAD. Adoption is again inferred (the ref resolves).
    .EXAMPLE
        wtw create my-feature --adopt
        Adopt an existing local branch where the branch name equals the
        task name. Equivalent to `--branch my-feature` here, or to the
        legacy `--no-branch`.
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
        [switch] $Adopt,
        [switch] $GtTrack,
        [string[]] $Alias
    )

    # --adopt is a friendlier alias for --no-branch (both opt into "adopt
    # an existing branch instead of creating one"). Collapse to a single
    # internal flag so downstream logic stays simple.
    if ($Adopt) { $NoBranch = $true }

    # Track whether the user explicitly passed --branch — used below to
    # decide if we should implicitly adopt when the ref already exists.
    $branchExplicit = -not [string]::IsNullOrWhiteSpace($Branch)

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

    if ((Get-WtwPropertyNames -Object $repoEntry.worktrees) -contains $Task) {
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

    # Implicit-adopt: when the user passed --branch explicitly AND the ref
    # already points at an existing branch (local or remote-tracking), we
    # adopt it rather than trying to create a new branch with the same
    # name (which would just fail with "branch already exists" from git).
    # This lets `wtw create my-feature --branch origin/my-feature` Just
    # Work — no extra --adopt/--no-branch needed.
    if (-not $NoBranch -and -not $From -and $branchExplicit) {
        git -C $mainRepo show-ref --verify --quiet "refs/heads/$Branch" 2>$null
        $branchExists = ($LASTEXITCODE -eq 0)
        if (-not $branchExists -and $Branch -match '^[^/]+/.+') {
            # Looks remote-ish (e.g. origin/foo) — verify it resolves.
            git -C $mainRepo rev-parse --verify "$Branch^{commit}" 2>&1 | Out-Null
            $branchExists = ($LASTEXITCODE -eq 0)
        }
        if ($branchExists) {
            Write-Host "  --branch '$Branch' refers to an existing ref; adopting (implies --adopt)." -ForegroundColor DarkCyan
            $NoBranch = $true
        }
    }

    if ($NoBranch) {
        # Adopt an existing branch. The ref in $Branch can be:
        #   - a local branch        → attach directly
        #   - a remote-tracking ref → create a local tracking branch so the
        #                             worktree stays on a real branch, not
        #                             detached HEAD
        # Validate first so we fail fast with a clear message instead of
        # letting git emit a cryptic worktree-add error mid-flight.
        $refResolved = git -C $mainRepo rev-parse --verify "$Branch^{commit}" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "--no-branch: ref '$Branch' not found in $repoName. Try 'git fetch' first, or pass --branch <existing-branch> / --branch origin/<name>."
            return
        }

        git -C $mainRepo show-ref --verify --quiet "refs/heads/$Branch" 2>$null
        $isLocalBranch = ($LASTEXITCODE -eq 0)

        if ($isLocalBranch) {
            Write-Host "  Adopting local branch: $Branch" -ForegroundColor Cyan
            $result = git -C $mainRepo worktree add $worktreePath $Branch 2>&1
        } else {
            # Treat as a remote-tracking ref (e.g. origin/foo). Derive the
            # local branch name by stripping the remote prefix — same DWIM
            # rule `git checkout --track origin/foo` uses.
            if ($Branch -notmatch '^[^/]+/.+') {
                Write-Error "--no-branch: ref '$Branch' resolves to a commit but is neither a local branch nor a remote-tracking ref. Use --from <ref> to start a new branch at a SHA/tag, or check out the branch first."
                return
            }
            $localName = $Branch -replace '^[^/]+/', ''
            git -C $mainRepo show-ref --verify --quiet "refs/heads/$localName" 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Error "--no-branch: cannot create local branch '$localName' tracking '$Branch' — a local branch named '$localName' already exists. Run 'wtw create $Task --no-branch --branch $localName' to adopt the local one instead."
                return
            }
            Write-Host "  Adopting remote branch: $Branch → local '$localName' (tracking)" -ForegroundColor Cyan
            $result = git -C $mainRepo worktree add -b $localName --track $worktreePath $Branch 2>&1
            if ($LASTEXITCODE -eq 0) { $Branch = $localName }
        }
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

    # All post-worktree-add setup (color, pretty name, workspace file, registry,
    # Superset/Codex/cmux/wmux/SourceGit/agentctl) is shared with `wtw add`.
    $meta = Initialize-WtwWorktreeMetadata `
        -RepoName $repoName -RepoEntry $repoEntry `
        -Task $Task -Branch $Branch `
        -WorktreePath $worktreePath -FolderSuffix $folderSuffix `
        -PrettyName $PrettyName -Color $Color `
        -Alias $Alias

    if (-not $meta.Success) {
        # The only failure mode today is a bad --color. We just created the
        # worktree, so unwind it — `wtw add` doesn't do this because it
        # adopts a pre-existing on-disk worktree it doesn't own.
        git -C $mainRepo worktree remove $worktreePath --force 2>$null | Out-Null
        return
    }

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
