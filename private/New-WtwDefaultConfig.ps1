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
        editor             = 'cursor'
        workspacesDir      = $workspacesDir
        staleWorktreePaths = @(
            (Join-Path -Path $HOME -ChildPath '.codex' -AdditionalChildPath 'worktrees'),
            (Join-Path -Path $HOME -ChildPath '.cursor' -AdditionalChildPath 'worktrees'),
            (Join-Path -Path $HOME -ChildPath 'conductor' -AdditionalChildPath 'workspaces')
        )
    }
}
