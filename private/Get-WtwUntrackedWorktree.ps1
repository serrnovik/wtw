function Get-WtwUntrackedWorktree {
    <#
    .SYNOPSIS
        Git worktrees of registered repos that wtw does not track yet.
    .DESCRIPTION
        Other tools (T3 Code, Codex, Cursor, plain ``git worktree add``) create
        worktrees next to a repo wtw already tracks. They show up here so
        ``wtw list`` can display them and ``wtw go`` / ``wtw open`` can adopt
        them on first use. The primary checkout, bare entries, and trees whose
        folder is gone (prunable) are skipped.
    .OUTPUTS
        PSCustomObject with RepoName, RepoEntry, Path, Branch, Detached, TaskName.
        TaskName is the folder name with the ``<repo>_`` prefix stripped, which is
        the key ``wtw add`` would register it under.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Registry,

        [string] $RepoName
    )

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($name in (Get-WtwPropertyNames -Object $Registry.repos)) {
        if ($RepoName -and $name -ne $RepoName) { continue }
        $repo = $Registry.repos.$name
        $mainPath = Get-WtwPropertyValue -Object $repo -Name 'mainPath'
        if (-not $mainPath -or -not (Test-Path -LiteralPath $mainPath)) { continue }

        $registeredMap = Get-WtwRegisteredWorktreePathMap -RepoEntry $repo
        $listed = @(Get-WtwGitWorktreeList -RepoPath $mainPath)
        $index = 0
        foreach ($wt in $listed) {
            $index++
            if ($wt.Bare -or $wt.Prunable) { continue }
            if ($index -eq 1 -or (Test-WtwSamePath $wt.Path $mainPath)) { continue }
            if ($registeredMap.Contains($wt.Path)) { continue }
            $canonical = Resolve-WtwRealPath $wt.Path
            if ($canonical -and $registeredMap.Contains($canonical)) { continue }
            if (-not (Test-Path -LiteralPath $wt.Path)) { continue }

            $leaf = Split-Path $wt.Path -Leaf
            $taskName = $leaf -replace "^$([regex]::Escape($name))_", ''
            if (-not $taskName) { $taskName = $leaf }

            [void]$items.Add([pscustomobject]@{
                    RepoName  = $name
                    RepoEntry = $repo
                    Path      = $wt.Path
                    Branch    = $wt.Branch
                    Detached  = [bool]$wt.Detached
                    TaskName  = $taskName
                })
        }
    }
    return @($items)
}

function Find-WtwUntrackedWorktree {
    <#
    .SYNOPSIS
        Untracked worktrees whose folder, task name, branch, or path match a query.
    .DESCRIPTION
        Tries exact, then prefix, then substring (case-insensitive) and returns
        the first non-empty tier, so an exact folder name beats a longer one
        that merely contains it. An absolute path matches that worktree's path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Registry,

        [Parameter(Mandatory)]
        [string] $Name,

        [string] $RepoName
    )

    $untracked = @(Get-WtwUntrackedWorktree -Registry $Registry -RepoName $RepoName)
    if ($untracked.Count -eq 0) { return @() }

    if ([System.IO.Path]::IsPathRooted($Name)) {
        return @($untracked | Where-Object { Test-WtwSamePath $_.Path $Name })
    }

    $needle = (ConvertTo-WtwLookupKey $Name)
    foreach ($mode in @('Exact', 'Prefix', 'Substring')) {
        $hits = @($untracked | Where-Object {
                $item = $_
                $candidates = @(
                    $item.TaskName
                    (Split-Path $item.Path -Leaf)
                    $item.Branch
                ) | Where-Object { $_ } | ForEach-Object { ConvertTo-WtwLookupKey $_ }
                $matched = $false
                foreach ($candidate in $candidates) {
                    $matched = switch ($mode) {
                        'Exact' { $candidate -eq $needle }
                        'Prefix' { $candidate.StartsWith($needle) }
                        'Substring' { $candidate.Contains($needle) }
                    }
                    if ($matched) { break }
                }
                $matched
            })
        if ($hits.Count -gt 0) { return $hits }
    }
    return @()
}

function Add-WtwUntrackedTarget {
    <#
    .SYNOPSIS
        Adopt one untracked worktree and return it in Resolve-WtwTarget's shape.
    .DESCRIPTION
        Runs ``wtw add`` (color, workspace file, editor registrations). The task
        key gets a numeric suffix when the folder name is already taken.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Item,

        [string] $Name
    )

    $existing = Get-WtwPropertyNames -Object $Item.RepoEntry.worktrees
    $task = $Item.TaskName
    $suffix = 2
    while ($existing -contains $task) {
        $task = "$($Item.TaskName)-$suffix"
        $suffix++
    }

    Write-WtwHost "  '$Name' is an untracked worktree of $($Item.RepoName): $($Item.Path)" -ForegroundColor Cyan
    Write-WtwHost '  Adding it to wtw...' -ForegroundColor Cyan
    $null = Add-WtwEntry -Path $Item.Path -Repo $Item.RepoName -Task $task

    $repo = (Get-WtwRegistry).repos.($Item.RepoName)
    if (-not $repo -or ((Get-WtwPropertyNames -Object $repo.worktrees) -notcontains $task)) {
        return $null
    }
    return [PSCustomObject]@{
        RepoName      = $Item.RepoName
        RepoEntry     = $repo
        TaskName      = $task
        WorktreeEntry = $repo.worktrees.$task
    }
}

function Remove-WtwGoneWorktree {
    <#
    .SYNOPSIS
        Drop registry entries for worktrees git has already removed.
    .DESCRIPTION
        A registered worktree is gone when its folder no longer exists and git
        either no longer lists it or lists it as prunable. Its registry entry,
        color assignment, and generated workspace file are removed. A repo
        whose main checkout is missing, or where git cannot list worktrees, is
        left alone: there is nothing to compare against.
    .OUTPUTS
        One "<repo>/<task>" string per removed entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Registry
    )

    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($repoName in (Get-WtwPropertyNames -Object $Registry.repos)) {
        $repo = $Registry.repos.$repoName
        $worktrees = Get-WtwPropertyValue -Object $repo -Name 'worktrees'
        $taskNames = Get-WtwPropertyNames -Object $worktrees
        if (-not $taskNames) { continue }
        $mainPath = Get-WtwPropertyValue -Object $repo -Name 'mainPath'
        if (-not $mainPath -or -not (Test-Path -LiteralPath $mainPath)) { continue }

        $listed = @(Get-WtwGitWorktreeList -RepoPath $mainPath)
        if ($listed.Count -eq 0) { continue }
        $live = @($listed | Where-Object { -not $_.Prunable })

        $gone = @(foreach ($task in $taskNames) {
                $path = Get-WtwPropertyValue -Object $worktrees.$task -Name 'path'
                if (-not $path -or (Test-Path -LiteralPath $path)) { continue }
                $stillListed = @($live | Where-Object { Test-WtwSamePath $_.Path $path }).Count -gt 0
                if (-not $stillListed) { $task }
            })
        if ($gone.Count -eq 0) { continue }

        $kept = [PSCustomObject]@{}
        foreach ($prop in $worktrees.PSObject.Properties) {
            if ($prop.Name -in $gone) {
                $workspace = Get-WtwPropertyValue -Object $prop.Value -Name 'workspace'
                if ($workspace -and (Test-Path -LiteralPath $workspace)) {
                    Remove-Item -LiteralPath $workspace -Force -ErrorAction SilentlyContinue
                }
                [void]$removed.Add("$repoName/$($prop.Name)")
            } else {
                $kept | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
            }
        }
        $repo.worktrees = $kept
    }

    if ($removed.Count -eq 0) { return @() }
    Save-WtwRegistry $Registry

    $colors = Get-WtwColors
    $assignments = [PSCustomObject]@{}
    foreach ($prop in $colors.assignments.PSObject.Properties) {
        if ($prop.Name -notin $removed) {
            $assignments | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
        }
    }
    $colors.assignments = $assignments
    Save-WtwColors $colors

    return @($removed)
}
