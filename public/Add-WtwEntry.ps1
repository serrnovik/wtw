function Add-WtwEntry {
    <#
    .SYNOPSIS
        Adopt an existing on-disk git worktree into wtw with full registration.
    .DESCRIPTION
        For a worktree directory that already exists (created by `git worktree
        add` outside wtw, or inherited from elsewhere). Wires it up with the
        same metadata that `wtw create` produces: color, workspace file from
        the repo template, pretty name with color circle, and registration
        in cmux / Codex / Superset / SourceGit / agentctl. Does NOT touch git
        — no branch is created, the worktree directory itself is left alone.

        Auto-detects the parent repo from the worktree's `.git` pointer file
        when -Repo is omitted. Use `wtw init` from inside the main checkout
        first if the parent repo isn't registered yet.
    .PARAMETER Path
        Path to the worktree directory (default: current directory).
    .PARAMETER Repo
        Parent repo alias. Auto-detected from the worktree's `.git` pointer
        when possible.
    .PARAMETER Task
        Registry key under the parent repo. Defaults to the worktree folder
        name (with the `${repoName}_` prefix stripped, if present).
    .PARAMETER Branch
        Override the branch name (default: auto-detected from git).
    .PARAMETER PrettyName
        Human-readable display name. A color-circle emoji is prepended
        automatically. Defaults to the folder suffix.
    .PARAMETER Color
        Color assignment. Same input format as `wtw create --color`: 'random'
        (default), '#rrggbb' / 'rrggbb', or a palette name.
    .EXAMPLE
        wtw add /path/to/snowmain1_foo --task foo
        Adopt an existing worktree as task 'foo' under its auto-detected parent.
        Generates the workspace file, picks a color, registers with cmux/SourceGit/etc.
    .EXAMPLE
        cd ../snowmain1_foo ; wtw add --task foo --color "forest green"
        Same, run from inside the worktree, with an explicit color.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Path,

        [string] $Repo,
        [string] $Task,
        [string] $Branch,
        [string] $PrettyName,
        [string] $Color
    )

    if (-not $Path) { $Path = (Get-Location).Path }
    $Path = [System.IO.Path]::GetFullPath($Path)

    if (-not (Test-Path $Path)) {
        Write-Error "Path does not exist: $Path"
        return
    }

    $gitDir = Join-Path $Path '.git'
    if (-not (Test-Path $gitDir)) {
        Write-Error "Not a git repository: $Path"
        return
    }

    $dirName = Split-Path $Path -Leaf
    Write-Host "  Path: $Path" -ForegroundColor Cyan

    # A worktree has a .git *file* (gitdir pointer); a primary checkout has
    # a .git *directory*. We only adopt worktrees here — use `wtw init` for
    # the primary checkout.
    $isWorktree = (Test-Path $gitDir -PathType Leaf)
    if (-not $isWorktree) {
        Write-Host "  This is a primary checkout, not a worktree." -ForegroundColor Cyan
        Write-Host "  Run 'wtw init' from inside it to register as a main repo." -ForegroundColor DarkGray
        return
    }

    # Auto-detect parent repo by asking git for the main worktree path —
    # `git worktree list --porcelain` always lists the primary checkout
    # first. Compare via realpath so symlink chains collapse (macOS routes
    # `/var/folders` and `/tmp` through `/private`, so `git`'s output and
    # the registry can end up referring to the same dir via different
    # strings).
    if (-not $Repo) {
        $porcelain = git -C $Path worktree list --porcelain 2>&1
        $parentRepoPath = $null
        if ($LASTEXITCODE -eq 0) {
            $first = ($porcelain -split "`n" | Select-String -Pattern '^worktree (.+)$' | Select-Object -First 1)
            if ($first) { $parentRepoPath = $first.Matches.Groups[1].Value.Trim() }
        }
        if (-not $parentRepoPath) {
            Write-Error "Could not determine main worktree path for $Path. Pass --repo <alias> explicitly."
            return
        }

        $parentCanonical = Resolve-WtwRealPath $parentRepoPath
        $registry = Get-WtwRegistry
        foreach ($name in (Get-WtwPropertyNames -Object $registry.repos)) {
            $r = $registry.repos.$name
            $rCanonical = Resolve-WtwRealPath $r.mainPath
            if ($rCanonical -eq $parentCanonical) {
                $Repo = $name
                Write-Host "  Detected parent repo: $Repo ($($r.mainPath))" -ForegroundColor Cyan
                break
            }
        }
        if (-not $Repo) {
            Write-Error "Parent repo at '$parentRepoPath' is not in the wtw registry. Run 'wtw init' from there first, or pass --repo <alias>."
            return
        }
    }

    $registry = Get-WtwRegistry
    if ((Get-WtwPropertyNames -Object $registry.repos) -notcontains $Repo) {
        Write-Error "Repo '$Repo' not in registry. Run 'wtw init' from the main repo first."
        return
    }
    $repoEntry = $registry.repos.$Repo

    # Default Task to the folder name with the `${repo}_` prefix stripped
    # (matches wtw create's folder convention).
    if (-not $Task) {
        $Task = $dirName -replace "^${Repo}_", ''
        Write-Host "  Task name: $Task" -ForegroundColor DarkGray
    }

    if ((Get-WtwPropertyNames -Object $repoEntry.worktrees) -contains $Task) {
        Write-Error "Worktree '$Task' is already registered under '$Repo'. Use 'wtw remove $Task' first, or pick a different --task."
        return
    }

    if (-not $Branch) {
        $Branch = git -C $Path branch --show-current 2>$null
        if (-not $Branch) { $Branch = '(detached)' }
    }
    Write-Host "  Branch:    $Branch" -ForegroundColor Green

    # FolderSuffix is what `wtw create` would have used — drives the workspace
    # filename. Strip the repo prefix when the dir follows the standard pattern.
    $folderSuffix = $dirName -replace "^${Repo}_", ''
    if (-not $folderSuffix) { $folderSuffix = $dirName }

    $meta = Initialize-WtwWorktreeMetadata `
        -RepoName $Repo -RepoEntry $repoEntry `
        -Task $Task -Branch $Branch `
        -WorktreePath $Path -FolderSuffix $folderSuffix `
        -PrettyName $PrettyName -Color $Color

    if (-not $meta.Success) { return }

    Write-Host ''
    Write-Host "  Adopted '$Task' under $Repo. Use 'wtw go $Task' to switch." -ForegroundColor Green
}
