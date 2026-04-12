function Invoke-WtwClean {
    <#
    .SYNOPSIS
        Find and remove stale AI-created worktrees.
    .DESCRIPTION
        Scans configured stale worktree paths (codex, cursor, conductor) and registered
        repos for detached HEAD worktrees. Shows sizes and allows interactive selection
        of which items to remove. Prunes git worktree metadata after removal.
    .PARAMETER DryRun
        Preview stale worktrees without removing anything.
    .PARAMETER Force
        Remove all stale worktrees without interactive prompting.
    .EXAMPLE
        wtw clean --dry-run
        List all stale worktrees with sizes but make no changes.
    .EXAMPLE
        wtw clean --force
        Remove all stale worktrees without prompting.
    #>
    [CmdletBinding()]
    param(
        [switch] $DryRun,
        [switch] $Force
    )

    $config = Get-WtwConfig
    if (-not $config) {
        Write-Error 'wtw not initialized. Run "wtw init" first.'
        return
    }

    Write-Host ''
    Write-Host '  Scanning for stale worktrees...' -ForegroundColor Cyan

    $staleItems = @()

    # 1. Scan stale worktree paths (AI tools)
    foreach ($stalePath in $config.staleWorktreePaths) {
        $resolvedPath = $stalePath.Replace('~', $HOME)
        $resolvedPath = [System.IO.Path]::GetFullPath($resolvedPath)

        if (-not (Test-Path $resolvedPath)) { continue }

        $toolName = Split-Path (Split-Path $resolvedPath -Parent) -Leaf
        if ($toolName -eq $HOME) { $toolName = Split-Path $resolvedPath -Leaf }

        # Find all repo-like directories under the stale path
        $dirs = Get-ChildItem -Path $resolvedPath -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $dirs) {
            # Look for repo directories inside (e.g., .codex/worktrees/3cc3/snowmain3/)
            $repoDirs = Get-ChildItem -Path $dir.FullName -Directory -ErrorAction SilentlyContinue
            if ($repoDirs) {
                foreach ($repoDir in $repoDirs) {
                    $gitFile = Join-Path $repoDir.FullName '.git'
                    if (Test-Path $gitFile) {
                        $size = Get-DirectorySize $repoDir.FullName
                        $staleItems += [PSCustomObject]@{
                            Source   = $toolName
                            Path     = $repoDir.FullName
                            Repo     = $repoDir.Name
                            Size     = $size
                            SizeStr  = Format-Size $size
                            Modified = $repoDir.LastWriteTime.ToString('yyyy-MM-dd')
                            Type     = 'ai-worktree'
                        }
                    }
                }
            } else {
                # Might be a flat worktree dir
                $gitFile = Join-Path $dir.FullName '.git'
                if (Test-Path $gitFile) {
                    $size = Get-DirectorySize $dir.FullName
                    $staleItems += [PSCustomObject]@{
                        Source   = $toolName
                        Path     = $dir.FullName
                        Repo     = $dir.Name
                        Size     = $size
                        SizeStr  = Format-Size $size
                        Modified = $dir.LastWriteTime.ToString('yyyy-MM-dd')
                        Type     = 'ai-worktree'
                    }
                }
            }
        }
    }

    # 2. Scan registered repos for detached HEAD worktrees
    $registry = Get-WtwRegistry
    foreach ($repoName in $registry.repos.PSObject.Properties.Name) {
        $repo = $registry.repos.$repoName
        if (-not (Test-Path $repo.mainPath)) { continue }

        $wtList = git -C $repo.mainPath worktree list --porcelain 2>$null
        if (-not $wtList) { continue }

        $currentWt = $null
        foreach ($line in $wtList) {
            if ($line -match '^worktree (.+)$') {
                $currentWt = @{ path = $Matches[1] }
            } elseif ($line -match '^HEAD (.+)$' -and $currentWt) {
                $currentWt.head = $Matches[1]
            } elseif ($line -eq 'detached' -and $currentWt) {
                # Skip main repo
                if ($currentWt.path -ne $repo.mainPath) {
                    # Skip if already in our stale list
                    $alreadyListed = $staleItems | Where-Object { $_.Path -eq $currentWt.path }
                    if (-not $alreadyListed -and (Test-Path $currentWt.path)) {
                        $dir = Get-Item $currentWt.path
                        $size = Get-DirectorySize $currentWt.path
                        $staleItems += [PSCustomObject]@{
                            Source   = 'git'
                            Path     = $currentWt.path
                            Repo     = $repoName
                            Size     = $size
                            SizeStr  = Format-Size $size
                            Modified = $dir.LastWriteTime.ToString('yyyy-MM-dd')
                            Type     = 'detached'
                        }
                    }
                }
            } elseif ($line -eq '' -and $currentWt) {
                $currentWt = $null
            }
        }
    }

    if ($staleItems.Count -eq 0) {
        Write-Host '  No stale worktrees found.' -ForegroundColor Green
        return
    }

    # Sort by size descending
    $staleItems = $staleItems | Sort-Object -Property Size -Descending

    $totalSize = ($staleItems | Measure-Object -Property Size -Sum).Sum

    Write-Host ''
    Write-Host "  Found $($staleItems.Count) stale worktrees ($(Format-Size $totalSize) total)" -ForegroundColor Yellow
    Write-Host ''
    Format-WtwTable $staleItems @('Source', 'Repo', 'SizeStr', 'Modified', 'Path')
    Write-Host ''

    if ($DryRun) {
        Write-Host '  (dry-run: no changes made)' -ForegroundColor DarkGray
        return
    }

    # Interactive selection
    if (-not $Force) {
        Write-Host '  Options:' -ForegroundColor Yellow
        Write-Host '    all    - Remove all stale worktrees'
        Write-Host '    none   - Cancel'
        Write-Host '    1,3,5  - Remove specific items (by number)'
        Write-Host ''
        $selection = Read-Host '  Select'

        if ($selection -eq 'none' -or -not $selection) {
            Write-Host '  Cancelled.' -ForegroundColor DarkGray
            return
        }

        if ($selection -ne 'all') {
            $indices = $selection -split '[,\s]+' | ForEach-Object { [int]$_ - 1 }
            $staleItems = $indices | ForEach-Object { $staleItems[$_] } | Where-Object { $_ }
        }
    }

    # Remove selected items
    $removedSize = 0
    $removedCount = 0

    foreach ($item in $staleItems) {
        Write-Host "  Removing: $($item.Path)..." -ForegroundColor Cyan -NoNewline

        try {
            # Try git worktree remove first
            $parentRepo = $null
            foreach ($rn in $registry.repos.PSObject.Properties.Name) {
                $r = $registry.repos.$rn
                if ($item.Path.StartsWith($r.mainPath) -or $item.Repo -eq (Split-Path $r.mainPath -Leaf)) {
                    $parentRepo = $r.mainPath
                    break
                }
            }

            if ($parentRepo -and (Test-Path $parentRepo)) {
                git -C $parentRepo worktree remove $item.Path --force 2>$null
            }

            # If still exists, force remove
            if (Test-Path $item.Path) {
                Remove-Item -Path $item.Path -Recurse -Force
            }

            $removedSize += $item.Size
            $removedCount++
            Write-Host ' done' -ForegroundColor Green
        } catch {
            Write-Host " FAILED: $_" -ForegroundColor Red
        }
    }

    # Prune all registered repos
    foreach ($repoName in $registry.repos.PSObject.Properties.Name) {
        $repo = $registry.repos.$repoName
        if (Test-Path $repo.mainPath) {
            git -C $repo.mainPath worktree prune 2>$null
        }
    }

    Write-Host ''
    Write-Host "  Removed $removedCount worktrees, freed $(Format-Size $removedSize)" -ForegroundColor Green
}

function Get-DirectorySize {
    param([string] $Path)
    try {
        if (-not $IsWindows) {
            # du -sk is orders of magnitude faster than Get-ChildItem recursion
            $duOutput = du -sk $Path 2>$null
            if ($duOutput -match '^\s*(\d+)') {
                return [long]$Matches[1] * 1024
            }
        }
        # Fallback for Windows
        $bytes = (Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        return [long]($bytes ?? 0)
    } catch {
        return 0
    }
}

function Format-Size {
    param([long] $Bytes)
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}
