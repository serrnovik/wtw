function Get-WtwNumericNameHint {
    <#
    .SYNOPSIS
        Explain a target name that arrived as a bare number, or return ''.
    .DESCRIPTION
        PowerShell's argument mode parses an unquoted `033` as the integer 33, so
        the leading zero is gone before wtw is called — it cannot be recovered,
        only explained. Worth saying out loud because worktree names like
        PF033/PF037 are exactly the shape that trips it.
    #>
    [CmdletBinding()]
    param([AllowNull()] [string] $Name)

    if ($Name -match '^\d+$') {
        return "PowerShell reads a bare number as a number, so a leading zero is lost before wtw sees it — quote it: '0$Name'."
    }
    return ''
}

function Resolve-WtwTarget {
    <#
    .SYNOPSIS
        Resolves a name/alias to a repo + optional worktree entry.
    .DESCRIPTION
        Unified resolution logic used by Enter, Remove, Open, etc.
        Resolution order:
          0. Absolute path (exact or prefix) -> matches worktree by filesystem path
          1. Exact repo alias match       -> returns repo (no worktree)
          1b. Repo name/alias prefix match -> unique prefix on repo names and aliases
          2. "alias-task" exact match      -> returns repo + worktree
          3. Bare task name exact match    -> searches all repos for unique match
          3b. Exact worktree alias         -> typed aliases set with ``wtw edit --alias``
          4. "alias-task" prefix match     -> unique prefix on task name (proj-b -> proj-backend-refactor)
          5. Bare task name prefix match   -> unique prefix across all repos
          5b. Substring match on task     -> "content" matches "my-content-engine"
          5c. Worktree alias prefix / substring
          5d. Pretty-name then branch match (lower priority than task / alias)
          6. Fuzzy match (Levenshtein)    -> auto-resolve if unique close match, suggest if tied
    .OUTPUTS
        PSCustomObject with: RepoName, RepoEntry, TaskName, WorktreeEntry
        or $null if nothing matched.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,

        # Not named `$Repo` — this function already uses `$repo` for registry
        # entries, and a [string] parameter would coerce those assignments.
        [string] $RepoAlias
    )

    $registry = Get-WtwRegistry
    $restrictRepo = $null
    if ($RepoAlias) {
        foreach ($rn in (Get-WtwPropertyNames -Object $registry.repos)) {
            $r = $registry.repos.$rn
            if ($rn -eq $RepoAlias -or (Test-WtwAliasMatch $r $RepoAlias)) {
                $restrictRepo = $rn
                break
            }
        }
        if (-not $restrictRepo) {
            Write-Error "Unknown repo '$RepoAlias' (not in registry)."
            return $null
        }
    }

    # 0. Absolute path resolution (exact then prefix)
    if ([System.IO.Path]::IsPathRooted($Name)) {
        $normInput = $Name.TrimEnd('/', '\')

        # 0a. Exact path match against repo main or worktree path
        foreach ($repoName in (Get-WtwPropertyNames -Object $registry.repos)) {
            if ($restrictRepo -and $repoName -ne $restrictRepo) { continue }
            $repo = $registry.repos.$repoName
            if ($repo.mainPath -and $repo.mainPath.TrimEnd('/', '\') -eq $normInput) {
                return [PSCustomObject]@{ RepoName=$repoName; RepoEntry=$repo; TaskName=$null; WorktreeEntry=$null }
            }
            if ($repo.worktrees) {
                foreach ($taskName in (Get-WtwPropertyNames -Object $repo.worktrees)) {
                    $wt = $repo.worktrees.$taskName
                    if ($wt.path -and $wt.path.TrimEnd('/', '\') -eq $normInput) {
                        return [PSCustomObject]@{ RepoName=$repoName; RepoEntry=$repo; TaskName=$taskName; WorktreeEntry=$wt }
                    }
                }
            }
        }

        # 0b. Path prefix match
        $pathMatches = @()
        foreach ($repoName in (Get-WtwPropertyNames -Object $registry.repos)) {
            if ($restrictRepo -and $repoName -ne $restrictRepo) { continue }
            $repo = $registry.repos.$repoName
            if ($repo.worktrees) {
                foreach ($taskName in (Get-WtwPropertyNames -Object $repo.worktrees)) {
                    $wt = $repo.worktrees.$taskName
                    if ($wt.path -and $wt.path.StartsWith($normInput)) {
                        $pathMatches += [PSCustomObject]@{ RepoName=$repoName; RepoEntry=$repo; TaskName=$taskName; WorktreeEntry=$wt }
                    }
                }
            }
        }
        if ($pathMatches.Count -eq 1) { return $pathMatches[0] }
        if ($pathMatches.Count -gt 1) {
            $names = ($pathMatches | ForEach-Object { $_.WorktreeEntry.path }) -join ', '
            Write-Error "Ambiguous path '$Name'. Matches: $names"
            return $null
        }

        Write-Error "No worktree found at path '$Name'. Run 'wtw list' to see available targets."
        return $null
    }

    # 1. Exact repo alias -> main repo
    foreach ($repoName in (Get-WtwPropertyNames -Object $registry.repos)) {
        if ($restrictRepo -and $repoName -ne $restrictRepo) { continue }
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

    # 1b. Repo name/alias prefix match
    $prefixRepos = @()
    foreach ($repoName in (Get-WtwPropertyNames -Object $registry.repos)) {
        if ($restrictRepo -and $repoName -ne $restrictRepo) { continue }
        $repo = $registry.repos.$repoName
        $matched = $false
        if ($repoName -like "${Name}*") { $matched = $true }
        if (-not $matched) {
            foreach ($alias in (Get-WtwRepoAliases $repo)) {
                if ($alias -like "${Name}*") { $matched = $true; break }
            }
        }
        if ($matched) {
            $prefixRepos += [PSCustomObject]@{
                RepoName       = $repoName
                RepoEntry      = $repo
                TaskName       = $null
                WorktreeEntry  = $null
            }
        }
    }
    if ($prefixRepos.Count -eq 1) { return $prefixRepos[0] }
    if ($prefixRepos.Count -gt 1) {
        $names = ($prefixRepos | ForEach-Object { $_.RepoName }) -join ', '
        Write-Error "Ambiguous prefix '$Name'. Matches repos: $names"
        return $null
    }

    # 2. "alias-task" exact match
    if ($Name -match '^(.+?)-(.+)$') {
        $aliasOrName = $Matches[1]
        $taskName    = $Matches[2]
        foreach ($repoName in (Get-WtwPropertyNames -Object $registry.repos)) {
            if ($restrictRepo -and $repoName -ne $restrictRepo) { continue }
            $repo = $registry.repos.$repoName
            if (((Test-WtwAliasMatch $repo $aliasOrName) -or $repoName -eq $aliasOrName) -and
                $repo.worktrees -and (Get-WtwPropertyNames -Object $repo.worktrees) -contains $taskName) {
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
    foreach ($repoName in (Get-WtwPropertyNames -Object $registry.repos)) {
        if ($restrictRepo -and $repoName -ne $restrictRepo) { continue }
        $repo = $registry.repos.$repoName
        if ($repo.worktrees -and (Get-WtwPropertyNames -Object $repo.worktrees) -contains $Name) {
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

    # 3b. Exact worktree alias (spaces/hyphens equivalent)
    $aliasExact = @(Get-WtwMatchingWorktrees -Registry $registry -RestrictRepo $restrictRepo -Name $Name -Mode Exact -Field Alias)
    if ($aliasExact.Count -eq 1) { return $aliasExact[0] }
    if ($aliasExact.Count -gt 1) {
        $names = ($aliasExact | ForEach-Object { "$($_.RepoName)/$($_.TaskName)" }) -join ', '
        Write-Error "Ambiguous alias '$Name'. Matches: $names"
        return $null
    }

    # 4. "alias-task" prefix match - proj-b matches proj-backend-refactor
    if ($Name -match '^(.+?)-(.+)$') {
        $aliasOrName  = $Matches[1]
        $taskPrefix   = $Matches[2]
        $prefixFound  = @()
        foreach ($repoName in (Get-WtwPropertyNames -Object $registry.repos)) {
            if ($restrictRepo -and $repoName -ne $restrictRepo) { continue }
            $repo = $registry.repos.$repoName
            if (-not ((Test-WtwAliasMatch $repo $aliasOrName) -or $repoName -eq $aliasOrName)) { continue }
            if (-not $repo.worktrees) { continue }
            foreach ($t in (Get-WtwPropertyNames -Object $repo.worktrees)) {
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
            # Prefer exact match; also treat emoji-suffixed names as exact (e.g. "018-019️" == "018-019")
            $exactMatch = @($prefixFound | Where-Object {
                $_.TaskName -eq $taskPrefix -or
                ($_.TaskName -replace '[^\x00-\x7F]', '') -eq $taskPrefix
            })
            if ($exactMatch.Count -eq 1) { return $exactMatch[0] }
            $names = ($prefixFound | ForEach-Object { $_.TaskName }) -join ', '
            Write-Error "Ambiguous prefix '$Name'. Matches: $names"
            return $null
        }
    }

    # 5. Bare task name prefix match -> search all repos
    $prefixFound = @()
    foreach ($repoName in (Get-WtwPropertyNames -Object $registry.repos)) {
        if ($restrictRepo -and $repoName -ne $restrictRepo) { continue }
        $repo = $registry.repos.$repoName
        if (-not $repo.worktrees) { continue }
        foreach ($t in (Get-WtwPropertyNames -Object $repo.worktrees)) {
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
        $exactMatch = @($prefixFound | Where-Object {
            $_.TaskName -eq $Name -or
            ($_.TaskName -replace '[^\x00-\x7F]', '') -eq $Name
        })
        if ($exactMatch.Count -eq 1) { return $exactMatch[0] }
        $names = ($prefixFound | ForEach-Object { "$($_.RepoName)/$($_.TaskName)" }) -join ', '
        Write-Error "Ambiguous prefix '$Name'. Matches: $names"
        return $null
    }

    # 5b. Substring match on task names -> "content" matches "my-content-engine"
    $escapedName = [WildcardPattern]::Escape($Name)
    $substringFound = @()
    foreach ($repoName in (Get-WtwPropertyNames -Object $registry.repos)) {
        if ($restrictRepo -and $repoName -ne $restrictRepo) { continue }
        $repo = $registry.repos.$repoName
        if (-not $repo.worktrees) { continue }
        foreach ($t in (Get-WtwPropertyNames -Object $repo.worktrees)) {
            if ($t -like "*${escapedName}*") {
                $substringFound += [PSCustomObject]@{
                    RepoName       = $repoName
                    RepoEntry      = $repo
                    TaskName       = $t
                    WorktreeEntry  = $repo.worktrees.$t
                }
            }
        }
    }

    if ($substringFound.Count -eq 1) {
        Write-Verbose "Substring match: '$Name' -> '$($substringFound[0].TaskName)'"
        return $substringFound[0]
    }
    if ($substringFound.Count -gt 1) {
        $names = ($substringFound | ForEach-Object { "$($_.RepoName)/$($_.TaskName)" }) -join ', '
        Write-Error "Ambiguous substring '$Name'. Matches: $names"
        return $null
    }

    # 5c. Worktree alias prefix, then substring
    $aliasPrefix = @(Get-WtwMatchingWorktrees -Registry $registry -RestrictRepo $restrictRepo -Name $Name -Mode Prefix -Field Alias)
    if ($aliasPrefix.Count -eq 1) { return $aliasPrefix[0] }
    if ($aliasPrefix.Count -gt 1) {
        $names = ($aliasPrefix | ForEach-Object { "$($_.RepoName)/$($_.TaskName)" }) -join ', '
        Write-Error "Ambiguous alias prefix '$Name'. Matches: $names"
        return $null
    }
    $aliasSub = @(Get-WtwMatchingWorktrees -Registry $registry -RestrictRepo $restrictRepo -Name $Name -Mode Substring -Field Alias)
    if ($aliasSub.Count -eq 1) { return $aliasSub[0] }
    if ($aliasSub.Count -gt 1) {
        $names = ($aliasSub | ForEach-Object { "$($_.RepoName)/$($_.TaskName)" }) -join ', '
        Write-Error "Ambiguous alias substring '$Name'. Matches: $names"
        return $null
    }

    # 5d. Pretty name then branch — lower priority so a task/alias always wins
    foreach ($field in @('Pretty', 'Branch')) {
        foreach ($mode in @('Exact', 'Prefix', 'Substring')) {
            $hits = @(Get-WtwMatchingWorktrees -Registry $registry -RestrictRepo $restrictRepo -Name $Name -Mode $mode -Field $field)
            if ($hits.Count -eq 1) {
                Write-Verbose "$field $mode match: '$Name' -> '$($hits[0].TaskName)'"
                return $hits[0]
            }
            if ($hits.Count -gt 1) {
                $names = ($hits | ForEach-Object { "$($_.RepoName)/$($_.TaskName)" }) -join ', '
                Write-Error "Ambiguous $($field.ToLowerInvariant()) $mode '$Name'. Matches: $names"
                return $null
            }
        }
    }

    # 6. Fuzzy match - find closest target by edit distance
    if ($restrictRepo) {
        $hint = Get-WtwNumericNameHint -Name $Name
        if ($hint) {
            Write-Error "Could not resolve '$Name' in repo '$restrictRepo'. $hint"
        } else {
            Write-Error "Could not resolve '$Name' in repo '$restrictRepo'."
        }
        return $null
    }

    $allTargets = Get-WtwAllTargetNames $registry
    $fuzzy = Resolve-WtwFuzzyMatch $Name $allTargets
    if ($fuzzy.Match) {
        return (Resolve-WtwTarget $fuzzy.Match)
    }
    # An all-digit name almost always means PowerShell ate a leading zero:
    # argument mode parses a bare `033` as the NUMBER 33, so wtw never sees the
    # original text. Suggest the targets that actually contain those digits,
    # which is far more useful here than edit-distance neighbours — '33' is one
    # character from a dozen unrelated aliases and close to none of them in
    # meaning.
    if ($Name -match '^\d+$') {
        $containing = @(Get-WtwAllTargetNames $registry | Where-Object { $_ -match $Name })
        $hint = Get-WtwNumericNameHint -Name $Name
        if ($containing.Count -gt 0) {
            Write-Error "Could not resolve '$Name'. $hint Targets containing '$Name': $($containing -join ', ')"
        } else {
            Write-Error "Could not resolve '$Name'. $hint Run 'wtw list' to see available targets."
        }
        return $null
    }

    if ($fuzzy.Suggestions.Count -gt 0) {
        $suggestions = $fuzzy.Suggestions -join ', '
        Write-Error "Could not resolve '$Name'. Did you mean: ${suggestions}?"
        return $null
    }

    Write-Error "Could not resolve '$Name'. Run 'wtw list' to see available targets."
    return $null
}
