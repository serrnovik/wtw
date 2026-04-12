function Add-WtwEntry {
    <#
    .SYNOPSIS
        Import an existing repo or worktree into the registry.
    .DESCRIPTION
        Registers an existing directory as a worktree in the wtw registry.
        Auto-detects the parent repo from the .git file for worktrees. Assigns
        a color and links any existing workspace file.
    .PARAMETER Path
        Path to the repo or worktree directory (default: current directory).
    .PARAMETER Repo
        Parent repo name for worktree registration.
    .PARAMETER Task
        Worktree task name to register under.
    .PARAMETER Branch
        Override the branch name (default: auto-detected from git).
    .EXAMPLE
        wtw add /path/to/worktree --repo my-app --task feature
        Import an existing worktree directory as task "feature" under repo "my-app".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Path,

        [string] $Repo,
        [string] $Task,
        [string] $Branch
    )

    # Resolve path
    if (-not $Path) { $Path = (Get-Location).Path }
    $Path = [System.IO.Path]::GetFullPath($Path)

    if (-not (Test-Path $Path)) {
        Write-Error "Path does not exist: $Path"
        return
    }

    # Must be a git repo
    $gitDir = Join-Path $Path '.git'
    if (-not (Test-Path $gitDir)) {
        Write-Error "Not a git repository: $Path"
        return
    }

    $dirName = Split-Path $Path -Leaf
    Write-Host "  Path: $Path" -ForegroundColor Cyan

    # Detect if this is a worktree (has .git file, not .git directory)
    $isWorktree = (Test-Path $gitDir -PathType Leaf)

    if ($isWorktree -and -not $Repo) {
        # Try to detect parent repo from .git file
        $gitContent = Get-Content $gitDir -Raw
        if ($gitContent -match 'gitdir:\s*(.+)') {
            $gitdirPath = $Matches[1].Trim()
            # gitdir points to something like /path/to/main/.git/worktrees/xxx
            if ($gitdirPath -match '(.+)/\.git/worktrees/') {
                $parentRepoPath = $Matches[1]
                $parentDirName = Split-Path $parentRepoPath -Leaf

                # Find matching repo in registry
                $registry = Get-WtwRegistry
                foreach ($name in $registry.repos.PSObject.Properties.Name) {
                    $r = $registry.repos.$name
                    if ([System.IO.Path]::GetFullPath($r.mainPath) -eq [System.IO.Path]::GetFullPath($parentRepoPath)) {
                        $Repo = $name
                        Write-Host "  Detected parent repo: $Repo ($parentRepoPath)" -ForegroundColor Cyan
                        break
                    }
                }
            }
        }
    }

    if ($isWorktree -and $Repo) {
        # Add as worktree to existing repo
        $registry = Get-WtwRegistry
        if ($registry.repos.PSObject.Properties.Name -notcontains $Repo) {
            Write-Error "Repo '$Repo' not in registry. Run 'wtw init' from the main repo first."
            return
        }

        if (-not $Task) {
            $Task = Read-Host "  Task name [$dirName]"
            if (-not $Task) { $Task = $dirName }
        }

        if (-not $Branch) {
            $Branch = git -C $Path branch --show-current 2>$null
            if (-not $Branch) { $Branch = '(detached)' }
        }

        Write-Host "  Adding as worktree '$Task' to repo '$Repo'" -ForegroundColor Cyan

        # Pick color
        $color = New-WtwColor -RepoName $Repo -TaskName $Task

        # Check for workspace file
        $config = Get-WtwConfig
        $wsFile = $null
        if ($config) {
            $wsDir = $config.workspacesDir.Replace('~', $HOME)
            $wsDir = [System.IO.Path]::GetFullPath($wsDir)
            $candidate = Join-Path $wsDir "${dirName}.code-workspace"
            if (Test-Path $candidate) { $wsFile = $candidate }
        }

        $wtEntry = [PSCustomObject]@{
            path      = $Path
            branch    = $Branch
            workspace = $wsFile
            color     = $color
            created   = (Get-Date -Format 'o')
        }
        $registry.repos.$Repo.worktrees | Add-Member -NotePropertyName $Task -NotePropertyValue $wtEntry -Force
        Save-WtwRegistry $registry

        Write-Host "  Branch:    $Branch" -ForegroundColor Green
        Write-Host "  Color:     $color" -ForegroundColor Green
        if ($wsFile) { Write-Host "  Workspace: $wsFile" -ForegroundColor Green }
        Write-Host ''
        Write-Host "  Added '$Task' to $Repo." -ForegroundColor Green
    } else {
        # Add as new repo (like init but for an external path)
        Write-Host "  This looks like a standalone repo." -ForegroundColor Cyan
        Write-Host "  Run 'wtw init' from inside it, or cd there and run 'wtw init'." -ForegroundColor DarkGray
        Write-Host "  For a worktree, use: wtw add $Path --repo <repo-name> --task <name>" -ForegroundColor DarkGray
    }
}
