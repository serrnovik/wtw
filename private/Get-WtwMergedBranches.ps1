function Get-WtwDefaultBranch {
    <#
    .SYNOPSIS
        Default branch for a checkout: origin/HEAD, then main, then master.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    if (-not (Test-Path $RepoPath)) { return $null }

    $originHead = git -C $RepoPath symbolic-ref --quiet refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and "$originHead" -match 'refs/remotes/origin/(.+)$') {
        return $Matches[1]
    }

    foreach ($candidate in @('main', 'master')) {
        git -C $RepoPath show-ref --verify --quiet "refs/heads/$candidate" 2>$null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }

    $current = git -C $RepoPath branch --show-current 2>$null
    if ($current) { return $current.Trim() }
    return $null
}

function Get-WtwCheckedOutBranches {
    <#
    .SYNOPSIS
        Local branch names currently checked out in any worktree of this repo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    $names = @()
    $porcelain = git -C $RepoPath worktree list --porcelain 2>$null
    foreach ($line in @($porcelain)) {
        if ($line -match '^branch refs/heads/(.+)$') {
            $names += $Matches[1]
        }
    }
    return @($names | Select-Object -Unique)
}

function Get-WtwMergedLocalBranches {
    <#
    .SYNOPSIS
        Local branches fully merged into the repo default branch, minus protected ones.
    .DESCRIPTION
        Skips the default branch and any branch still checked out in a worktree.
        Those need ``wtw remove`` first; ``git branch -d`` cannot delete them.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath,

        [Parameter(Mandatory)]
        [string] $RepoName,

        [string] $DefaultBranch
    )

    $result = [PSCustomObject]@{
        Items         = @()
        Skipped       = @()
        DefaultBranch = $DefaultBranch
    }

    if (-not $DefaultBranch) {
        $DefaultBranch = Get-WtwDefaultBranch -RepoPath $RepoPath
        $result.DefaultBranch = $DefaultBranch
    }
    if (-not $DefaultBranch) { return $result }

    $checkedOut = @(Get-WtwCheckedOutBranches -RepoPath $RepoPath)
    $lines = git -C $RepoPath branch --merged $DefaultBranch --format='%(refname:short)' 2>$null
    if ($LASTEXITCODE -ne 0) { return $result }

    $items = @()
    $skipped = @()
    foreach ($raw in @($lines)) {
        $name = "$raw".Trim()
        if (-not $name) { continue }
        if ($name -eq $DefaultBranch) { continue }
        if ($name -in $checkedOut) {
            $skipped += $name
            continue
        }
        $items += [PSCustomObject]@{
            Repo   = $RepoName
            Branch = $name
            Into   = $DefaultBranch
            Status = 'merged'
        }
    }

    $result.Items = @($items)
    $result.Skipped = @($skipped)
    return $result
}

function Resolve-WtwCleanScope {
    <#
    .SYNOPSIS
        Decide whether clean runs worktrees, merged branches, or both.
    #>
    [CmdletBinding()]
    param(
        [switch] $All,
        [switch] $Worktrees,
        [switch] $Branches,
        [string] $Choice
    )

    if ($All -or ($Worktrees -and $Branches)) {
        return [PSCustomObject]@{ Worktrees = $true; Branches = $true }
    }
    if ($Worktrees) {
        return [PSCustomObject]@{ Worktrees = $true; Branches = $false }
    }
    if ($Branches) {
        return [PSCustomObject]@{ Worktrees = $false; Branches = $true }
    }

    if (-not $PSBoundParameters.ContainsKey('Choice')) {
        Write-Host '  Clean what?' -ForegroundColor Yellow
        Write-Host '    worktrees  stale AI / detached worktrees'
        Write-Host '    branches   local branches already merged into the default branch'
        Write-Host '    all        both'
        Write-Host ''
        $Choice = Read-Host '  Select'
    }

    $token = if ($null -eq $Choice) { '' } else { $Choice.Trim().ToLowerInvariant() }
    switch -Regex ($token) {
        '^(all|a|3)$' { return [PSCustomObject]@{ Worktrees = $true; Branches = $true } }
        '^(worktrees?|wt|w|1)$' { return [PSCustomObject]@{ Worktrees = $true; Branches = $false } }
        '^(branches?|br|b|2)$' { return [PSCustomObject]@{ Worktrees = $false; Branches = $true } }
    }

    Write-Host '  Cancelled.' -ForegroundColor DarkGray
    return $null
}

function Select-WtwCleanItems {
    <#
    .SYNOPSIS
        Shared all / none / 1,3,5 picker used by worktree and branch clean.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Items,

        [switch] $Force,

        [string] $Noun = 'items'
    )

    if ($Force -or @($Items).Count -eq 0) { return @($Items) }

    Write-Host '  Options:' -ForegroundColor Yellow
    Write-Host "    all    - Remove all $Noun"
    Write-Host '    none   - Cancel'
    Write-Host '    1,3,5  - Remove specific items (by number)'
    Write-Host ''
    $selection = Read-Host '  Select'

    if ($selection -eq 'none' -or -not $selection) {
        Write-Host '  Cancelled.' -ForegroundColor DarkGray
        return $null
    }

    if ($selection -eq 'all') { return @($Items) }

    $indices = $selection -split '[,\s]+' | ForEach-Object { [int]$_ - 1 }
    return @($indices | ForEach-Object { $Items[$_] } | Where-Object { $_ })
}
