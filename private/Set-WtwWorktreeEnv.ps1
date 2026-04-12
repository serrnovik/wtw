function Set-WtwWorktreeEnv {
    <#
    .SYNOPSIS
        Set worktree environment variables for dev tooling integration.
    .DESCRIPTION
        Sets both WTW_* (wtw-specific) and DEV_WORKTREE_* (generic, tool-agnostic)
        environment variables based on the current worktree session. For worktree
        sessions, computes a port offset from the worktree index. For main repo
        sessions, clears all worktree variables.
    .PARAMETER TaskName
        The worktree task/branch name. Null or empty for the main repo session.
    .PARAMETER RepoEntry
        The registry repo object used to determine worktree index ordering.
    #>
    [CmdletBinding()]
    param(
        [string] $TaskName,      # null/empty for main repo
        [PSObject] $RepoEntry
    )

    if ($TaskName) {
        # Worktree session — compute index from registry order
        $index = 0
        if ($RepoEntry.worktrees) {
            $i = 1
            foreach ($t in $RepoEntry.worktrees.PSObject.Properties.Name) {
                if ($t -eq $TaskName) { $index = $i; break }
                $i++
            }
        }
        $portOffset = $index * 100

        # WTW-specific
        $env:WTW_WORKTREE_ID    = $TaskName
        $env:WTW_WORKTREE_INDEX = $index

        # Generic (tool-agnostic) — usable by jax, deploy scripts, any CI tool
        $env:DEV_WORKTREE_ID             = $TaskName
        $env:DEV_WORKTREE_INDEX          = $index
        $env:DEV_WORKTREE_DASHED_POSTFIX = "-${TaskName}"
        $env:DEV_WORKTREE_PORT_OFFSET    = $portOffset
    } else {
        # Main repo session — clear worktree vars
        $env:WTW_WORKTREE_ID    = ''
        $env:WTW_WORKTREE_INDEX = ''

        $env:DEV_WORKTREE_ID             = ''
        $env:DEV_WORKTREE_INDEX          = ''
        $env:DEV_WORKTREE_DASHED_POSTFIX = ''
        $env:DEV_WORKTREE_PORT_OFFSET    = '0'
    }
}
