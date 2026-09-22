function Get-WtwGitWorktreeList {
    <#
    .SYNOPSIS
        Parse ``git worktree list --porcelain`` into objects.
    .DESCRIPTION
        First entry is the primary checkout. Linked trees follow. Paths are
        the strings git emitted (not yet realpath-canonicalized).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    $items = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path $RepoPath)) { return @() }

    $porcelain = git -C $RepoPath worktree list --porcelain 2>$null
    if (-not $porcelain) { return @() }

    $current = $null
    foreach ($line in @($porcelain)) {
        if ($line -match '^worktree (.+)$') {
            if ($null -ne $current) {
                [void]$items.Add([pscustomobject]$current)
            }
            $current = [ordered]@{
                Path      = $Matches[1]
                Head      = $null
                Branch    = $null
                Detached  = $false
                Bare      = $false
                Locked    = $false
                Prunable  = $false
            }
            continue
        }
        if ($null -eq $current) { continue }
        if ($line -match '^HEAD (.+)$') {
            $current.Head = $Matches[1]
            continue
        }
        if ($line -match '^branch refs/heads/(.+)$') {
            $current.Branch = $Matches[1]
            continue
        }
        if ($line -eq 'detached') {
            $current.Detached = $true
            continue
        }
        if ($line -eq 'bare') {
            $current.Bare = $true
            continue
        }
        if ($line -match '^locked') {
            $current.Locked = $true
            continue
        }
        if ($line -match '^prunable') {
            $current.Prunable = $true
        }
    }
    if ($null -ne $current) {
        [void]$items.Add([pscustomobject]$current)
    }
    return @($items)
}

function Test-WtwSamePath {
    <#
    .SYNOPSIS
        Compare two filesystem paths after symlink / firmlink resolution.
    #>
    [CmdletBinding()]
    param(
        [string] $Left,
        [string] $Right
    )

    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }

    $leftResolved = Resolve-WtwRealPath $Left
    $rightResolved = Resolve-WtwRealPath $Right
    if ($IsWindows) {
        $leftNorm = $leftResolved.TrimEnd('\')
        $rightNorm = $rightResolved.TrimEnd('\')
        return $leftNorm -ieq $rightNorm
    }

    $leftNorm = $leftResolved.TrimEnd('/')
    $rightNorm = $rightResolved.TrimEnd('/')
    return $leftNorm -ceq $rightNorm
}

function Get-WtwRegisteredWorktreePathMap {
    <#
    .SYNOPSIS
        Map worktree path (raw and canonical) → registry task name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $RepoEntry
    )

    $map = @{}
    $worktrees = Get-WtwPropertyValue -Object $RepoEntry -Name 'worktrees'
    foreach ($taskName in (Get-WtwPropertyNames -Object $worktrees)) {
        $wt = $worktrees.$taskName
        $path = Get-WtwPropertyValue -Object $wt -Name 'path'
        if (-not $path) { continue }
        $map[$path] = $taskName
        $canonical = Resolve-WtwRealPath $path
        if ($canonical) { $map[$canonical] = $taskName }
    }
    return $map
}

function Test-WtwWorktreeDirty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path $Path)) { return $false }
    $status = git -C $Path status --porcelain 2>$null
    return [bool]$status
}

function Test-WtwBranchMergedInto {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath,

        [Parameter(Mandatory)]
        [string] $Branch,

        [Parameter(Mandatory)]
        [string] $DefaultBranch
    )

    git -C $RepoPath merge-base --is-ancestor $Branch $DefaultBranch 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Get-WtwLinkedWorktreeItems {
    <#
    .SYNOPSIS
        Extra git worktrees on registered repos (not the primary checkout).
    .DESCRIPTION
        Used by ``wtw clean --worktrees`` (unregistered + detached) and
        ``wtw clean --linked`` (those plus wtw-tracked extras). Skips the
        directory the command is running from so you cannot delete the
        tree you are standing in.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Registry,

        [switch] $IncludeRegistered,
        [switch] $IncludeUnregistered,
        [switch] $IncludeDetached
    )

    $includeUnregistered = [bool]$IncludeUnregistered
    $includeRegistered = [bool]$IncludeRegistered
    $includeDetached = [bool]$IncludeDetached
    $noKindSelected = -not $includeRegistered -and -not $includeUnregistered
    if ($noKindSelected) {
        $includeUnregistered = $true
    }

    $currentPath = Resolve-WtwRealPath (Get-Location).Path
    $items = @()

    foreach ($repoName in (Get-WtwPropertyNames -Object $Registry.repos)) {
        $repo = $Registry.repos.$repoName
        $mainPath = Get-WtwPropertyValue -Object $repo -Name 'mainPath'
        if (-not $mainPath -or -not (Test-Path $mainPath)) { continue }

        $defaultBranch = Get-WtwDefaultBranch -RepoPath $mainPath
        $registeredMap = Get-WtwRegisteredWorktreePathMap -RepoEntry $repo
        $listed = @(Get-WtwGitWorktreeList -RepoPath $mainPath)
        $index = 0
        foreach ($wt in $listed) {
            $index++
            if ($wt.Bare) { continue }

            $isPrimaryCheckout = ($index -eq 1) -or (Test-WtwSamePath $wt.Path $mainPath)
            if ($isPrimaryCheckout) { continue }
            if (Test-WtwSamePath $wt.Path $currentPath) { continue }

            $canonical = Resolve-WtwRealPath $wt.Path
            $taskName = $null
            if ($registeredMap.Contains($canonical)) {
                $taskName = $registeredMap[$canonical]
            } elseif ($registeredMap.Contains($wt.Path)) {
                $taskName = $registeredMap[$wt.Path]
            }
            $isRegistered = $null -ne $taskName
            $isDetached = [bool]$wt.Detached

            $includeThis = $false
            if ($isDetached -and $includeDetached) {
                $includeThis = $true
            } elseif ($isRegistered -and $includeRegistered) {
                $includeThis = $true
            } elseif (-not $isRegistered -and $includeUnregistered) {
                $includeThis = $true
            }
            if (-not $includeThis) { continue }

            $exists = Test-Path $wt.Path
            $size = if ($exists) { Get-DirectorySize $wt.Path } else { [long]0 }
            $modified = '-'
            if ($exists) {
                $modified = (Get-Item $wt.Path).LastWriteTime.ToString('yyyy-MM-dd')
            }
            $dirty = '-'
            if ($exists) {
                $dirty = if (Test-WtwWorktreeDirty $wt.Path) { 'yes' } else { 'no' }
            }
            $branch = '-'
            if ($wt.Branch) {
                $branch = $wt.Branch
            } elseif ($isDetached) {
                $branch = '(detached)'
            }
            $merged = '-'
            $hasMergeCheck = $wt.Branch -and $defaultBranch
            if ($hasMergeCheck) {
                $isMerged = Test-WtwBranchMergedInto -RepoPath $mainPath -Branch $wt.Branch -DefaultBranch $defaultBranch
                $merged = if ($isMerged) { 'yes' } else { 'no' }
            }

            $status = if ($isRegistered) { 'registered' } else { 'unregistered' }
            $type = if ($isDetached) { 'detached' } else { 'linked' }

            $items += [PSCustomObject]@{
                Source   = 'git'
                Path     = $wt.Path
                Repo     = $repoName
                Branch   = $branch
                Status   = $status
                Task     = $taskName
                Merged   = $merged
                Dirty    = $dirty
                Size     = $size
                SizeStr  = Format-Size $size
                Modified = $modified
                Type     = $type
                MainPath = $mainPath
            }
        }
    }

    return @($items)
}
