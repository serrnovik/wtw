function Get-WtwWorktreeAliases {
    <#
    .SYNOPSIS
        Optional typed aliases stored on a worktree entry (not the derived alias-task names).
    #>
    param([AllowNull()] [PSObject] $Worktree)

    $result = @()
    if (-not $Worktree) { return , $result }
    if ((Get-WtwPropertyNames -Object $Worktree) -contains 'aliases' -and $Worktree.aliases) {
        $result = @($Worktree.aliases)
    } elseif ((Get-WtwPropertyNames -Object $Worktree) -contains 'alias' -and $Worktree.alias) {
        $result = @($Worktree.alias)
    }
    return , @($result | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
}

function ConvertTo-WtwLookupKey {
    <#
    .SYNOPSIS
        Normalise a search/alias string so spaces, hyphens, and slashes match.
    #>
    param([AllowNull()] [string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $t = $Value.Trim()
    $t = $t -replace '^[\p{So}\p{Sk}\p{Cn}\s]+', ''
    return ($t.ToLowerInvariant() -replace '[-_/\s]+', ' ').Trim()
}

function Join-WtwTargetName {
    <#
    .SYNOPSIS
        Join leftover positionals so ``wtw go onboarding video`` keeps the space.
    #>
    param([AllowNull()] [string[]] $Parts)

    if (-not $Parts) { return '' }
    return (@($Parts | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join ' ')
}

function ConvertTo-WtwShellAliasName {
    <#
    .SYNOPSIS
        Turn a typed alias into a shell-safe name (spaces become hyphens).
    #>
    param([AllowNull()] [string] $Alias)

    if ([string]::IsNullOrWhiteSpace($Alias)) { return '' }
    return (($Alias.Trim() -replace '\s+', '-'))
}

function Test-WtwLookupMatch {
    param(
        [string] $Query,
        [AllowNull()] [string] $Candidate,
        [ValidateSet('Exact', 'Prefix', 'Substring')]
        [string] $Mode
    )

    $q = ConvertTo-WtwLookupKey $Query
    $c = ConvertTo-WtwLookupKey $Candidate
    if (-not $q -or -not $c) { return $false }
    switch ($Mode) {
        'Exact' { return $q -eq $c }
        'Prefix' { return $c.StartsWith($q) }
        'Substring' { return $c.Contains($q) }
    }
    return $false
}

function Test-WtwAliasClearToken {
    param([AllowNull()] [string[]] $Value)

    $first = @($Value | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if ($first.Count -eq 0) { return $false }
    $token = ConvertTo-WtwLookupKey "$($first[0])"
    return $token -in @('-', 'none', 'off', 'clear')
}

function Get-WtwMatchingWorktrees {
    <#
    .SYNOPSIS
        Collect worktree targets whose task / alias / branch / pretty name matches.
    #>
    param(
        [Parameter(Mandatory)] [PSObject] $Registry,
        [string] $RestrictRepo,
        [Parameter(Mandatory)] [string] $Name,
        [ValidateSet('Exact', 'Prefix', 'Substring')]
        [string] $Mode,
        [ValidateSet('Task', 'Alias', 'Branch', 'Pretty')]
        [string] $Field
    )

    $found = @()
    foreach ($repoName in (Get-WtwPropertyNames -Object $Registry.repos)) {
        if ($RestrictRepo -and $repoName -ne $RestrictRepo) { continue }
        $repo = $Registry.repos.$repoName
        if (-not $repo.worktrees) { continue }
        foreach ($taskName in (Get-WtwPropertyNames -Object $repo.worktrees)) {
            $wt = $repo.worktrees.$taskName
            $candidates = switch ($Field) {
                'Task' { @($taskName) }
                'Alias' { @(Get-WtwWorktreeAliases $wt) }
                'Branch' { @(Get-WtwPropertyValue -Object $wt -Name 'branch') }
                'Pretty' { @(Get-WtwPropertyValue -Object $wt -Name 'prettyName') }
            }
            $hit = $false
            foreach ($candidate in $candidates) {
                if (Test-WtwLookupMatch -Query $Name -Candidate $candidate -Mode $Mode) {
                    $hit = $true
                    break
                }
            }
            if ($hit) {
                $found += [PSCustomObject]@{
                    RepoName      = $repoName
                    RepoEntry     = $repo
                    TaskName      = $taskName
                    WorktreeEntry = $wt
                }
            }
        }
    }
    return @($found)
}

function Test-WtwWorktreeAliasCollision {
    <#
    .SYNOPSIS
        Return $true (and write the error) when a worktree alias collides globally.
    #>
    param(
        [Parameter(Mandatory)] [PSObject] $Registry,
        [Parameter(Mandatory)] [string] $RepoName,
        [Parameter(Mandatory)] [string] $TaskName,
        [AllowEmptyCollection()] [string[]] $Aliases
    )

    foreach ($newAlias in @($Aliases)) {
        $key = ConvertTo-WtwLookupKey $newAlias
        if (-not $key) { continue }
        foreach ($existingName in (Get-WtwPropertyNames -Object $Registry.repos)) {
            $existingRepo = $Registry.repos.$existingName
            if ((ConvertTo-WtwLookupKey $existingName) -eq $key) {
                Write-Error "Alias '$newAlias' collides with repo '$existingName'."
                return $true
            }
            foreach ($repoAlias in (Get-WtwRepoAliases $existingRepo)) {
                if ((ConvertTo-WtwLookupKey $repoAlias) -eq $key) {
                    Write-Error "Alias '$newAlias' is already used by repo '$existingName'."
                    return $true
                }
            }
            if (-not $existingRepo.worktrees) { continue }
            foreach ($task in (Get-WtwPropertyNames -Object $existingRepo.worktrees)) {
                if ($existingName -eq $RepoName -and $task -eq $TaskName) { continue }
                if ((ConvertTo-WtwLookupKey $task) -eq $key) {
                    Write-Error "Alias '$newAlias' collides with worktree '$existingName/$task'."
                    return $true
                }
                foreach ($wtAlias in (Get-WtwWorktreeAliases $existingRepo.worktrees.$task)) {
                    if ((ConvertTo-WtwLookupKey $wtAlias) -eq $key) {
                        Write-Error "Alias '$newAlias' is already used by worktree '$existingName/$task'."
                        return $true
                    }
                }
            }
        }
    }
    return $false
}
