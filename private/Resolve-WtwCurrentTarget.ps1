function Resolve-WtwCurrentTarget {
    # Detect current repo/worktree from cwd, return a name usable by Open-WtwWorkspace
    $repoName, $repo = Get-WtwRepoFromCwd
    if (-not $repoName) { return $null }

    # Check if we're in a worktree
    $cwd = (Get-Location).Path
    if ($repo.worktrees) {
        foreach ($taskName in $repo.worktrees.PSObject.Properties.Name) {
            $wt = $repo.worktrees.$taskName
            if ($wt.path -and [System.IO.Path]::GetFullPath($wt.path) -eq [System.IO.Path]::GetFullPath($cwd)) {
                return $taskName
            }
        }
    }

    # We're in the main repo - return first alias
    $aliases = Get-WtwRepoAliases $repo
    if ($aliases.Count -gt 0) { return $aliases[0] }
    return $repoName
}
