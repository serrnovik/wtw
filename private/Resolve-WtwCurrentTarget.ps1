function Resolve-WtwCurrentTarget {
    # Detect current repo/worktree from cwd, return a name usable by Open-WtwWorkspace
    $repoName, $repo = Get-WtwRepoFromCwd
    if (-not $repoName) { return $null }

    # Check if we're in a worktree
    $root = Resolve-WtwRepoRoot
    if ($repo.worktrees -and $root) {
        $rootResolved = [System.IO.Path]::GetFullPath($root)
        foreach ($taskName in (Get-WtwPropertyNames -Object $repo.worktrees)) {
            $wt = $repo.worktrees.$taskName
            if ($wt.path -and [System.IO.Path]::GetFullPath($wt.path) -eq $rootResolved) {
                return $taskName
            }
        }
    }

    # We're in the main repo - return first alias
    $aliases = Get-WtwRepoAliases $repo
    if ($aliases.Count -gt 0) { return $aliases[0] }
    return $repoName
}
