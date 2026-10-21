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

        $listed = @(Get-WtwGitWorktreeList -RepoPath $mainPath)
        $worktrees = Get-WtwPropertyValue -Object $repo -Name 'worktrees'
        $registeredPaths = @(foreach ($task in (Get-WtwPropertyNames -Object $worktrees)) {
                Get-WtwPropertyValue -Object $worktrees.$task -Name 'path'
            })
        Initialize-WtwRealPathCache -Paths (@($mainPath) + $registeredPaths + @($listed | ForEach-Object { $_.Path }))
        $registeredMap = Get-WtwRegisteredWorktreePathMap -RepoEntry $repo
        $index = 0
        foreach ($wt in $listed) {
            $index++
            if ($wt.Bare -or $wt.Prunable) { continue }
            if ($index -eq 1 -or (Test-WtwSamePath $wt.Path $mainPath)) { continue }
            if ($registeredMap.Contains($wt.Path)) { continue }
            if (-not (Test-Path -LiteralPath $wt.Path)) { continue }
            $canonical = Resolve-WtwRealPath $wt.Path
            if ($canonical -and $registeredMap.Contains($canonical)) { continue }

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

function Find-WtwGoneWorktree {
    <#
    .SYNOPSIS
        Registered worktrees git has already removed.
    .DESCRIPTION
        A registered worktree is gone when its folder no longer exists and git
        either no longer lists it or lists it as prunable. git is only asked
        for repos that have a missing folder, so the usual case costs one
        Test-Path per entry. A repo whose main checkout is missing, or where
        git cannot list worktrees, is skipped: there is nothing to compare
        against.
    .OUTPUTS
        PSCustomObject with RepoName, TaskName, Path, Key ("<repo>/<task>").
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Registry
    )

    $gone = [System.Collections.Generic.List[object]]::new()
    foreach ($repoName in (Get-WtwPropertyNames -Object $Registry.repos)) {
        $repo = $Registry.repos.$repoName
        $worktrees = Get-WtwPropertyValue -Object $repo -Name 'worktrees'
        $taskNames = Get-WtwPropertyNames -Object $worktrees
        if (-not $taskNames) { continue }

        $missing = @(foreach ($task in $taskNames) {
                $path = Get-WtwPropertyValue -Object $worktrees.$task -Name 'path'
                if ($path -and -not (Test-Path -LiteralPath $path)) {
                    [pscustomobject]@{ RepoName = $repoName; TaskName = $task; Path = $path; Key = "$repoName/$task" }
                }
            })
        if ($missing.Count -eq 0) { continue }

        $mainPath = Get-WtwPropertyValue -Object $repo -Name 'mainPath'
        if (-not $mainPath -or -not (Test-Path -LiteralPath $mainPath)) { continue }
        $listed = @(Get-WtwGitWorktreeList -RepoPath $mainPath)
        if ($listed.Count -eq 0) { continue }

        # A missing folder git still lists as live (an unmounted drive) stays.
        $live = @($listed | Where-Object { -not $_.Prunable } | ForEach-Object { $_.Path })
        Initialize-WtwRealPathCache -Paths $live
        $liveKeys = @($live | ForEach-Object { ConvertTo-WtwPathKey $_ })
        foreach ($item in $missing) {
            if ($liveKeys -notcontains (ConvertTo-WtwPathKey $item.Path)) { [void]$gone.Add($item) }
        }
    }
    return @($gone)
}

function Remove-WtwGoneWorktree {
    <#
    .SYNOPSIS
        Drop registry entries for worktrees git has already removed.
    .DESCRIPTION
        Removes each entry from Find-WtwGoneWorktree (or ``-Gone``) together
        with its color assignment and generated workspace file.
    .OUTPUTS
        One "<repo>/<task>" string per removed entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Registry,

        [object[]] $Gone
    )

    if (-not $PSBoundParameters.ContainsKey('Gone')) {
        $Gone = @(Find-WtwGoneWorktree -Registry $Registry)
    }
    $goneKeys = @($Gone | ForEach-Object { $_.Key })
    if ($goneKeys.Count -eq 0) { return @() }

    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($repoName in @($Gone | ForEach-Object { $_.RepoName } | Select-Object -Unique)) {
        $repo = $Registry.repos.$repoName
        $kept = [PSCustomObject]@{}
        foreach ($prop in $repo.worktrees.PSObject.Properties) {
            if ("$repoName/$($prop.Name)" -in $goneKeys) {
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
