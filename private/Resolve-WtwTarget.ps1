function Resolve-WtwTarget {
    <#
    .SYNOPSIS
        Resolves a name/alias to a repo + optional worktree entry.
    .DESCRIPTION
        Unified resolution logic used by Enter, Remove, Open, etc.
        Resolution order:
          1. Exact repo alias match -> returns repo (no worktree)
          2. "alias-task" format    -> returns repo + worktree
          3. Bare task name         -> searches all repos for unique match
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

    # 2. "alias-task" format
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

    # 3. Bare task name -> search all repos
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

    Write-Error "Could not resolve '$Name'. Run 'wtw list' to see available targets."
    return $null
}
