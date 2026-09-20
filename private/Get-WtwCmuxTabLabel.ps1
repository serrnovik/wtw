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

function Get-WtwCmuxTabTitleOverridePath {
    <#
    .SYNOPSIS
        Temp file the cmux ``agent-action.ps1`` title guard reads instead of 🌴 wtw.
    .DESCRIPTION
        The Command Palette / tab-bar launcher starts a job that re-applies its
        action title for several seconds. wtw writes the real tab label here so
        that guard keeps the worktree name instead of stomping it back to 🌴.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspaceId,
        [Parameter(Mandatory)][string] $SurfaceId
    )

    $safe = ($WorkspaceId + '.' + $SurfaceId) -replace '[^\w:.-]', '_'
    return Join-Path ([System.IO.Path]::GetTempPath()) "wtw-cmux-tab-$safe"
}

function Set-WtwCmuxTabTitleOverride {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspaceId,
        [Parameter(Mandatory)][string] $SurfaceId,
        [Parameter(Mandatory)][string] $Title
    )

    # Inline the path so this still works after Restore-WtwInstalledModule
    # invalidates by-name lookup of other private helpers.
    $safe = ($WorkspaceId + '.' + $SurfaceId) -replace '[^\w:.-]', '_'
    $path = Join-Path ([System.IO.Path]::GetTempPath()) "wtw-cmux-tab-$safe"
    Set-Content -LiteralPath $path -Value $Title -Encoding utf8 -NoNewline
    return $path
}

function Set-WtwCmuxCurrentTabLabel {
    <#
    .SYNOPSIS
        Rename the current cmux surface and pin that title for the action-tab guard.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $PrettyName,
        $GetTabLabel,
        $SetOverride,
        $InvokeRawCommand,
        [string] $CmuxBin
    )

    if (-not ($PrettyName -and $env:CMUX_WORKSPACE_ID -and $env:CMUX_SURFACE_ID)) { return }

    $tabLabel = if ($GetTabLabel) { & $GetTabLabel -PrettyName $PrettyName } else { Get-WtwCmuxTabLabel -PrettyName $PrettyName }
    if ($SetOverride) {
        & $SetOverride -WorkspaceId $env:CMUX_WORKSPACE_ID -SurfaceId $env:CMUX_SURFACE_ID -Title $tabLabel | Out-Null
    } else {
        Set-WtwCmuxTabTitleOverride -WorkspaceId $env:CMUX_WORKSPACE_ID -SurfaceId $env:CMUX_SURFACE_ID -Title $tabLabel | Out-Null
    }

    if ($InvokeRawCommand) {
        & $InvokeRawCommand -CmuxBin $CmuxBin -ArgumentList @(
            'rename-tab',
            '--workspace', $env:CMUX_WORKSPACE_ID,
            '--surface', $env:CMUX_SURFACE_ID,
            $tabLabel
        ) | Out-Null
    }
}

function Get-WtwCmuxRemoteSessionPrettyName {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Remote)

    $workspace = Get-WtwCmuxCurrentWorkspaceObject
    if ($workspace) {
        $fromWorkspace = Get-WtwCmuxWorkspaceName -Workspace $workspace
        if ($fromWorkspace) { return $fromWorkspace }
    }

    $prefix = Get-WtwHostTitlePrefix -HostEntry $Remote.HostEntry
    if ($Remote.Name) { return "$prefix$($Remote.Name)" }
    return "$prefix$($Remote.HostSelector)"
}
