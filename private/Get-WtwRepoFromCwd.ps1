function Get-WtwRepoFromCwd {
    [CmdletBinding()]
    param()

    $root = Resolve-WtwRepoRoot
    if (-not $root) { return $null, $null }

    $registry = Get-WtwRegistry
    $repoNames = (Get-WtwPropertyNames -Object $registry.repos)
    foreach ($name in $repoNames) {
        $repo = $registry.repos.$name
        $mainResolved = [System.IO.Path]::GetFullPath($repo.mainPath)
        if ($mainResolved -ieq [System.IO.Path]::GetFullPath($root)) {
            return $name, $repo
        }
        # Check if we're inside a worktree of this repo
        if ($repo.worktrees) {
            foreach ($taskName in (Get-WtwPropertyNames -Object $repo.worktrees)) {
                $wt = $repo.worktrees.$taskName
                $wtResolved = [System.IO.Path]::GetFullPath($wt.path)
                if ($wtResolved -ieq [System.IO.Path]::GetFullPath($root)) {
                    return $name, $repo
                }
            }
        }
    }
    return $null, $null
}
