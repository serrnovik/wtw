function New-WtwDefaultConfig {
    [CmdletBinding()]
    param()

    $workspacesDir = if ($IsWindows) {
        Join-Path $HOME 'Data' 'code-workspaces'
    } else {
        Join-Path $HOME 'Data' 'code-workspaces'
    }

    return [PSCustomObject]@{
        editor             = 'cursor'
        workspacesDir      = $workspacesDir
        staleWorktreePaths = @(
            (Join-Path $HOME '.codex' 'worktrees'),
            (Join-Path $HOME '.cursor' 'worktrees'),
            (Join-Path $HOME '.superset' 'worktrees'),
            (Join-Path $HOME 'conductor' 'workspaces')
        )
    }
}
