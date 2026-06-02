function Initialize-WtwCmuxCurrentSession {
    <#
    .SYNOPSIS
        Apply wtw metadata to the current cmux workspace and optional terminal session.
    .DESCRIPTION
        Resolves the wtw target from the current directory. When requested, runs the
        normal wtw session initialization first so PowerShell terminals get the same
        title/env/session setup as `wtw go <target>`.
    #>
    [CmdletBinding()]
    param(
        [switch] $ApplyTerminalSession
    )

    if (-not $env:CMUX_WORKSPACE_ID) { return }

    $currentName = Resolve-WtwCurrentTarget
    if (-not $currentName) { return }

    $target = & { Resolve-WtwTarget $currentName } 6>$null
    if (-not $target) { return }

    $dir = if ($target.WorktreeEntry) { $target.WorktreeEntry.path } else { $target.RepoEntry.mainPath }
    if (-not ($dir -and (Test-Path $dir))) { return }

    $prettyName = if ($target.WorktreeEntry -and $target.WorktreeEntry.PSObject.Properties.Name -contains 'prettyName' -and $target.WorktreeEntry.prettyName) {
        $target.WorktreeEntry.prettyName
    } elseif ($target.TaskName) {
        $target.TaskName
    } else {
        Split-Path ([System.IO.Path]::GetFullPath($dir)) -Leaf
    }
    $color = if ($target.WorktreeEntry -and $target.WorktreeEntry.PSObject.Properties.Name -contains 'color') { $target.WorktreeEntry.color } else { $null }
    $statusValue = if ($target.TaskName) { "$($target.RepoName)/$($target.TaskName)" } else { $target.RepoName }
    $cmuxBin = Get-WtwCmuxBin
    $invokeRawCommand = Get-Command Invoke-WtwCmuxRawCommand -ErrorAction SilentlyContinue

    if ($ApplyTerminalSession) {
        Enter-WtwWorktree -Name $currentName
    }

    if ($invokeRawCommand) {
        & $invokeRawCommand -CmuxBin $cmuxBin -ArgumentList @('workspace-action', '--workspace', $env:CMUX_WORKSPACE_ID, '--action', 'rename', '--title', $prettyName) | Out-Null
        if ($color) {
            & $invokeRawCommand -CmuxBin $cmuxBin -ArgumentList @('workspace-action', '--workspace', $env:CMUX_WORKSPACE_ID, '--action', 'set-color', '--color', $color) | Out-Null
        }
        if ($statusValue) {
            & $invokeRawCommand -CmuxBin $cmuxBin -ArgumentList @('set-status', 'wtw', $statusValue, '--workspace', $env:CMUX_WORKSPACE_ID, '--icon', 'git-branch', '--color', ($color ?? '#7A4FD8'), '--priority', '90') | Out-Null
        }
    }
    if ($env:CMUX_SURFACE_ID -and $prettyName -and $invokeRawCommand) {
        # Tab label gets the console+tree wtw icon prefix; the workspace title (above)
        # stays as the bare pretty name for the sidebar/switcher.
        $tabLabel = Get-WtwCmuxTabLabel -PrettyName $prettyName
        & $invokeRawCommand -CmuxBin $cmuxBin -ArgumentList @('rename-tab', '--workspace', $env:CMUX_WORKSPACE_ID, '--surface', $env:CMUX_SURFACE_ID, $tabLabel) | Out-Null
    }
}
