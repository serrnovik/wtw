function Invoke-WtwClean {
    <#
    .SYNOPSIS
        Find and remove stale AI worktrees and/or local branches already merged.
    .DESCRIPTION
        Two independent sweeps:

          --worktrees   stale AI folders (codex / cursor / conductor) and
                        detached-HEAD worktrees on registered repos
          --branches    local branches fully merged into the repo default
                        branch, skipping any branch still checked out
          --all         both

        With none of those flags, asks which sweep to run. Item pick
        (all / none / 1,3,5) still applies unless ``--force``.
    .PARAMETER All
        Run both sweeps.
    .PARAMETER Worktrees
        Only the stale-worktree sweep.
    .PARAMETER Branches
        Only the merged-branch sweep.
    .PARAMETER DryRun
        Preview without removing anything.
    .PARAMETER Force
        Remove every listed item without the all/none/1,3,5 picker.
    .EXAMPLE
        wtw clean
        Ask worktrees / branches / all, then pick items.
    .EXAMPLE
        wtw clean --branches --dry-run
        List leftover merged local branches.
    .EXAMPLE
        wtw clean --all --force
        Remove every stale worktree and every leftover merged branch.
    #>
    [CmdletBinding()]
    param(
        [switch] $All,
        [switch] $Worktrees,
        [switch] $Branches,
        [switch] $DryRun,
        [switch] $Force
    )

    $config = Get-WtwConfig
    if (-not $config) {
        Write-Error 'wtw not initialized. Run "wtw init" first.'
        return
    }

    Write-Host ''
    $scope = Resolve-WtwCleanScope -All:$All -Worktrees:$Worktrees -Branches:$Branches
    if (-not $scope) { return }

    $registry = Get-WtwRegistry
    $didWork = $false

    if ($scope.Worktrees) {
        $didWork = $true
        Invoke-WtwCleanWorktrees -Config $config -Registry $registry -DryRun:$DryRun -Force:$Force
    }
    if ($scope.Branches) {
        $didWork = $true
        Invoke-WtwCleanMergedBranches -Registry $registry -DryRun:$DryRun -Force:$Force
    }
    if (-not $didWork) {
        Write-Host '  Nothing selected.' -ForegroundColor DarkGray
    }
}

function Invoke-WtwCleanWorktrees {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] $Registry,
        [switch] $DryRun,
        [switch] $Force
    )

    Write-Host '  Scanning for stale worktrees...' -ForegroundColor Cyan

    $supersetGuard = @{}
    if (Get-Command superset -ErrorAction SilentlyContinue) {
        $projJson = & superset projects list --json 2>$null
        $projExit = $LASTEXITCODE
        $wsJson = & superset workspaces list --json 2>$null
        $wsExit = $LASTEXITCODE
        if ($projExit -eq 0 -and $wsExit -eq 0 -and $projJson -and $wsJson) {
            try {
                $projs = $projJson | ConvertFrom-Json
                $ws = $wsJson | ConvertFrom-Json
                $projById = @{}
                foreach ($p in $projs) { $projById[$p.id] = $p }
                foreach ($w in $ws) {
                    $p = $projById[$w.projectId]
                    if (-not $p) { continue }
                    foreach ($key in @($p.slug, $p.id)) {
                        if (-not $key) { continue }
                        $supersetGuard[(Join-Path $HOME ".superset/worktrees/$key/$($w.name)")] = $true
                        $supersetGuard[(Join-Path $HOME ".superset/worktrees/$key/$($w.branch)")] = $true
                    }
                }
            } catch { }
        }
    }

    $staleItems = @()
    $stalePaths = @()
    if ((Get-WtwPropertyNames -Object $Config) -contains 'staleWorktreePaths' -and $Config.staleWorktreePaths) {
        $stalePaths = @($Config.staleWorktreePaths)
    }

    foreach ($stalePath in $stalePaths) {
        $resolvedPath = $stalePath.Replace('~', $HOME)
        $resolvedPath = [System.IO.Path]::GetFullPath($resolvedPath)

        if (-not (Test-Path $resolvedPath)) { continue }

        $toolName = Split-Path (Split-Path $resolvedPath -Parent) -Leaf
        if ($toolName -eq $HOME) { $toolName = Split-Path $resolvedPath -Leaf }

        $dirs = Get-ChildItem -Path $resolvedPath -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $dirs) {
            $repoDirs = Get-ChildItem -Path $dir.FullName -Directory -ErrorAction SilentlyContinue
            if ($repoDirs) {
                foreach ($repoDir in $repoDirs) {
                    if ($supersetGuard.ContainsKey($repoDir.FullName)) { continue }
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
                if ($supersetGuard.ContainsKey($dir.FullName)) { continue }
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

    foreach ($repoName in (Get-WtwPropertyNames -Object $Registry.repos)) {
        $repo = $Registry.repos.$repoName
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
                if ($currentWt.path -ne $repo.mainPath) {
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

    $staleItems = @($staleItems | Sort-Object -Property Size -Descending)
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

    $staleItems = Select-WtwCleanItems -Items $staleItems -Force:$Force -Noun 'stale worktrees'
    if ($null -eq $staleItems) { return }

    $removedSize = 0
    $removedCount = 0

    foreach ($item in $staleItems) {
        Write-Host "  Removing: $($item.Path)..." -ForegroundColor Cyan -NoNewline

        try {
            $parentRepo = $null
            foreach ($rn in (Get-WtwPropertyNames -Object $Registry.repos)) {
                $r = $Registry.repos.$rn
                if ($item.Path.StartsWith($r.mainPath) -or $item.Repo -eq (Split-Path $r.mainPath -Leaf)) {
                    $parentRepo = $r.mainPath
                    break
                }
            }

            if ($parentRepo -and (Test-Path $parentRepo)) {
                git -C $parentRepo worktree remove $item.Path --force 2>$null
            }

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

    foreach ($repoName in (Get-WtwPropertyNames -Object $Registry.repos)) {
        $repo = $Registry.repos.$repoName
        if (Test-Path $repo.mainPath) {
            git -C $repo.mainPath worktree prune 2>$null
        }
    }

    Write-Host ''
    Write-Host "  Removed $removedCount worktrees, freed $(Format-Size $removedSize)" -ForegroundColor Green
}

function Invoke-WtwCleanMergedBranches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Registry,
        [switch] $DryRun,
        [switch] $Force
    )

    Write-Host '  Scanning for merged local branches...' -ForegroundColor Cyan

    $items = @()
    $skipped = @()
    foreach ($repoName in (Get-WtwPropertyNames -Object $Registry.repos)) {
        $repo = $Registry.repos.$repoName
        $mainPath = Get-WtwPropertyValue -Object $repo -Name 'mainPath'
        if (-not $mainPath -or -not (Test-Path $mainPath)) { continue }

        $found = Get-WtwMergedLocalBranches -RepoPath $mainPath -RepoName $repoName
        if ($found.Items) { $items += @($found.Items) }
        foreach ($name in @($found.Skipped)) {
            $skipped += "$repoName/$name"
        }
    }

    if ($items.Count -eq 0) {
        Write-Host '  No leftover merged branches found.' -ForegroundColor Green
        if ($skipped.Count -gt 0) {
            Write-Host "  Still checked out in a worktree (use wtw remove): $($skipped -join ', ')" -ForegroundColor DarkGray
        }
        return
    }

    Write-Host ''
    Write-Host "  Found $($items.Count) merged local branch(es)" -ForegroundColor Yellow
    Write-Host ''
    Format-WtwTable $items @('Repo', 'Branch', 'Into', 'Status')
    Write-Host ''
    if ($skipped.Count -gt 0) {
        Write-Host "  Skipped (still in a worktree): $($skipped -join ', ')" -ForegroundColor DarkGray
        Write-Host ''
    }

    if ($DryRun) {
        Write-Host '  (dry-run: no changes made)' -ForegroundColor DarkGray
        return
    }

    $items = Select-WtwCleanItems -Items $items -Force:$Force -Noun 'merged branches'
    if ($null -eq $items) { return }

    $removed = 0
    foreach ($item in $items) {
        $repo = $Registry.repos.($item.Repo)
        $mainPath = Get-WtwPropertyValue -Object $repo -Name 'mainPath'
        Write-Host "  Deleting $($item.Repo)/$($item.Branch)..." -ForegroundColor Cyan -NoNewline
        git -C $mainPath branch -d $item.Branch 2>$null
        if ($LASTEXITCODE -eq 0) {
            $removed++
            Write-Host ' done' -ForegroundColor Green
        } else {
            Write-Host ' FAILED (not fully merged, or still checked out)' -ForegroundColor Red
        }
    }

    Write-Host ''
    Write-Host "  Deleted $removed merged branch(es)." -ForegroundColor Green
}

function Get-DirectorySize {
    param([string] $Path)
    try {
        if (-not $IsWindows) {
            $duOutput = du -sk $Path 2>$null
            if ($duOutput -match '^\s*(\d+)') {
                return [long]$Matches[1] * 1024
            }
        }
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
