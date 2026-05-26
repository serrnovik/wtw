function Restore-WtwInstalledModule {
    <#
    .SYNOPSIS
        Re-imports the installed wtw module after repo-local session scripts run.

    .DESCRIPTION
        Some repositories import their checked-out devops/worktree-workspace
        module from start-repository-session.ps1. When wtw switches into an old
        worktree, that stale local import can replace the freshly installed wtw
        functions in the current shell. Restore the installed module after
        session setup unless the caller explicitly opts into repo-local module
        development with WTW_USE_REPO_MODULE.
    #>
    [CmdletBinding()]
    param()

    if ($env:WTW_USE_REPO_MODULE) {
        return
    }

    $installedModule = Join-Path $HOME '.wtw/module/wtw.psm1'
    if (-not (Test-Path $installedModule)) {
        return
    }

    Import-Module $installedModule -Global -Force -DisableNameChecking -Verbose:$false -Debug:$false 1>$null 4>$null 5>$null 6>$null
}
