<#
.SYNOPSIS
    Creates a new default wtw configuration object.

.DESCRIPTION
    Returns a PSCustomObject with editor, workspacesDir, and staleWorktreePaths defaults
    suitable for first-time setup.

.EXAMPLE
    New-WtwDefaultConfig

.NOTES
    No external dependencies.
#>
function New-WtwDefaultConfig {
    [CmdletBinding()]
    param()

    $workspacesDir = if ($IsWindows) {
        Join-Path -Path $HOME -ChildPath 'Data' -AdditionalChildPath 'code-workspaces'
    } else {
        Join-Path -Path $HOME -ChildPath 'Data' -AdditionalChildPath 'code-workspaces'
    }

    return [PSCustomObject]@{
        # Accepts a single name or an ordered chain (["cursor","code"]) — first
        # runnable wins, so the same config works on machines with different
        # editors installed.
        editor             = 'cursor'
        workspacesDir      = $workspacesDir
        # Remote machines for `wtw --on <host>`. Populated by `wtw host add`.
        hosts              = [PSCustomObject]@{}
        staleWorktreePaths = @(
            (Join-Path -Path $HOME -ChildPath '.codex' -AdditionalChildPath 'worktrees'),
            (Join-Path -Path $HOME -ChildPath '.cursor' -AdditionalChildPath 'worktrees'),
            (Join-Path -Path $HOME -ChildPath 'conductor' -AdditionalChildPath 'workspaces')
        )
        agentctl           = [PSCustomObject]@{
            enabled        = $true
            defaultProfile = 'team'
            repoProfiles   = [PSCustomObject]@{}
        }
    }
}
