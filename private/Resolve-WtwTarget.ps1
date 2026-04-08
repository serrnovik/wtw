function Resolve-WtwTarget {
    <#
    .SYNOPSIS
        Resolves a name/alias to a repo + optional worktree entry.
    .DESCRIPTION
        Unified resolution logic used by Enter, Remove, Open, etc.
        Resolution order:
          1. Exact repo alias match       -> returns repo (no worktree)
          2. "alias-task" exact match      -> returns repo + worktree
          3. Bare task name exact match    -> searches all repos for unique match
          4. "alias-task" prefix match     -> unique prefix on task name (sn3-b -> sn3-brain-stores-refactor)
          5. Bare task name prefix match   -> unique prefix across all repos
          6. Fuzzy match (Levenshtein)    -> auto-resolve if unique close match, suggest if tied
    .OUTPUTS
        PSCustomObject with: RepoName, RepoEntry, TaskName, WorktreeEntry
        or $null if nothing matched.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name
    )

    $registry = Get-WtwRegistry

    # 1. Exact repo alias -> main repo
    foreach ($repoName in $registry.repos.PSObject.Properties.Name) {
        $repo = $registry.repos.$repoName
        if ((Test-WtwAliasMatch $repo $Name) -or $repoName -eq $Name) {
            return [PSCustomObject]@{
                RepoName       = $repoName
                RepoEntry      = $repo
                TaskName       = $null
                WorktreeEntry  = $null
            }
        }
    }

    # 2. "alias-task" exact match
    if ($Name -match '^(.+?)-(.+)$') {
        $aliasOrName = $Matches[1]
        $taskName    = $Matches[2]
        foreach ($repoName in $registry.repos.PSObject.Properties.Name) {
            $repo = $registry.repos.$repoName
            if (((Test-WtwAliasMatch $repo $aliasOrName) -or $repoName -eq $aliasOrName) -and
                $repo.worktrees -and $repo.worktrees.PSObject.Properties.Name -contains $taskName) {
                return [PSCustomObject]@{
                    RepoName       = $repoName
                    RepoEntry      = $repo
                    TaskName       = $taskName
                    WorktreeEntry  = $repo.worktrees.$taskName
                }
            }
        }
    }

    # 3. Bare task name exact match -> search all repos
    $found = @()
    foreach ($repoName in $registry.repos.PSObject.Properties.Name) {
        $repo = $registry.repos.$repoName
        if ($repo.worktrees -and $repo.worktrees.PSObject.Properties.Name -contains $Name) {
            $found += [PSCustomObject]@{
                RepoName       = $repoName
                RepoEntry      = $repo
                TaskName       = $Name
                WorktreeEntry  = $repo.worktrees.$Name
            }
        }
    }

    if ($found.Count -eq 1) { return $found[0] }
    if ($found.Count -gt 1) {
        Write-Error "Ambiguous name '$Name'. Found in multiple repos. Use 'alias-task' format."
        return $null
    }

    # 4. "alias-task" prefix match — sn3-b matches sn3-brain-stores-refactor
    if ($Name -match '^(.+?)-(.+)$') {
        $aliasOrName  = $Matches[1]
        $taskPrefix   = $Matches[2]
        $prefixFound  = @()
        foreach ($repoName in $registry.repos.PSObject.Properties.Name) {
            $repo = $registry.repos.$repoName
            if (-not ((Test-WtwAliasMatch $repo $aliasOrName) -or $repoName -eq $aliasOrName)) { continue }
            if (-not $repo.worktrees) { continue }
            foreach ($t in $repo.worktrees.PSObject.Properties.Name) {
                if ($t -like "${taskPrefix}*") {
                    $prefixFound += [PSCustomObject]@{
                        RepoName       = $repoName
                        RepoEntry      = $repo
                        TaskName       = $t
                        WorktreeEntry  = $repo.worktrees.$t
                    }
                }
            }
        }
        if ($prefixFound.Count -eq 1) { return $prefixFound[0] }
        if ($prefixFound.Count -gt 1) {
            $names = ($prefixFound | ForEach-Object { $_.TaskName }) -join ', '
            Write-Error "Ambiguous prefix '$Name'. Matches: $names"
            return $null
        }
    }

    # 5. Bare task name prefix match -> search all repos
    $prefixFound = @()
    foreach ($repoName in $registry.repos.PSObject.Properties.Name) {
        $repo = $registry.repos.$repoName
        if (-not $repo.worktrees) { continue }
        foreach ($t in $repo.worktrees.PSObject.Properties.Name) {
            if ($t -like "${Name}*") {
                $prefixFound += [PSCustomObject]@{
                    RepoName       = $repoName
                    RepoEntry      = $repo
                    TaskName       = $t
                    WorktreeEntry  = $repo.worktrees.$t
                }
            }
        }
    }

    if ($prefixFound.Count -eq 1) { return $prefixFound[0] }
    if ($prefixFound.Count -gt 1) {
        $names = ($prefixFound | ForEach-Object { "$($_.RepoName)/$($_.TaskName)" }) -join ', '
        Write-Error "Ambiguous prefix '$Name'. Matches: $names"
        return $null
    }

    # 6. Fuzzy match — find closest target by edit distance
    $allTargets = Get-WtwAllTargetNames $registry
    $maxDist = [Math]::Max(2, [Math]::Floor($Name.Length / 3))
    $fuzzyMatches = @()
    foreach ($candidate in $allTargets) {
        $dist = Get-WtwEditDistance $Name $candidate
        if ($dist -le $maxDist) {
            $fuzzyMatches += [PSCustomObject]@{ Target = $candidate; Dist = $dist }
        }
    }
    $fuzzyMatches = $fuzzyMatches | Sort-Object Dist

    if ($fuzzyMatches.Count -gt 0) {
        $best = $fuzzyMatches[0]
        $tied = @($fuzzyMatches | Where-Object { $_.Dist -eq $best.Dist })
        if ($tied.Count -eq 1) {
            Write-Host "  Fuzzy match: '$Name' → '$($best.Target)'" -ForegroundColor Yellow
            return (Resolve-WtwTarget $best.Target)
        } else {
            $suggestions = ($tied | ForEach-Object { $_.Target }) -join ', '
            Write-Error "Could not resolve '$Name'. Did you mean: ${suggestions}?"
            return $null
        }
    }

    Write-Error "Could not resolve '$Name'. Run 'wtw list' to see available targets."
    return $null
}
