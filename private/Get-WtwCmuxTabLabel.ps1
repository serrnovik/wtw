function Get-WtwCmuxTabLabel {
    <#
    .SYNOPSIS
        Build the cmux tab label for a wtw-managed surface: a console+tree icon
        (marking the tab as a wtw worktree shell) followed by the workspace pretty name.
    .DESCRIPTION
        Keeps the tab visually distinct from agent/jax tabs while resting. jax and the
        agent tab updater temporarily override this label during a run; this is the
        label the tab returns to (or sits at) when idle.

        The icon defaults to 🖥️🌳 (console + worktree) and can be overridden per machine
        via $env:WTW_TAB_ICON without a code change.
    .PARAMETER PrettyName
        The workspace pretty name (e.g. "PF-018 training materials").
    .PARAMETER Icon
        Override the leading icon. Falls back to $env:WTW_TAB_ICON, then 🖥️🌳.
    .EXAMPLE
        Get-WtwCmuxTabLabel -PrettyName 'PF-018'   # -> '🖥️🌳 PF-018'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $PrettyName,
        [string] $Icon
    )

    if (-not $Icon) {
        $Icon = if ($env:WTW_TAB_ICON) { $env:WTW_TAB_ICON } else { '🖥️🌳' }
    }

    $name = if ($null -ne $PrettyName) { $PrettyName.Trim() } else { '' }
    if ([string]::IsNullOrWhiteSpace($name)) { return $Icon }

    return "$Icon $name"
}
