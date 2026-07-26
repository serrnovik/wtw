
function Get-WtwAllTargetNames {
    <#
    .SYNOPSIS
        Returns all resolvable target names (repo names, aliases, worktree names, alias-task combos).
    #>
    param([PSObject] $Registry)
    $targets = @()
    foreach ($repoName in (Get-WtwPropertyNames -Object $Registry.repos)) {
        $repo = $Registry.repos.$repoName
        $targets += $repoName
        foreach ($alias in (Get-WtwRepoAliases $repo)) {
            $targets += $alias
        }
        if ($repo.worktrees) {
            foreach ($task in (Get-WtwPropertyNames -Object $repo.worktrees)) {
                $targets += $task
                foreach ($alias in (Get-WtwRepoAliases $repo)) {
                    $targets += "$alias-$task"
                }
            }
        }
    }
    return $targets | Select-Object -Unique
}
