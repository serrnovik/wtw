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
    # Pre-resolve the tab-label helper NOW, before Enter-WtwWorktree's Restore-WtwInstalledModule
    # does a -Force re-import (which invalidates by-name resolution of module-private functions
    # for the still-running code). Same reason $invokeRawCommand is captured up here.
    $getTabLabel = Get-Command Get-WtwCmuxTabLabel -ErrorAction SilentlyContinue

    if ($ApplyTerminalSession) {
        # Enter-WtwWorktree (at its end) also pushes cmux metadata on the plain `wtw go`
        # path. Flag the reentrant case so it doesn't double-apply: we still run the
        # metadata block below ourselves.
        $script:WtwCmuxApplyingFromInit = $true
        try { Enter-WtwWorktree -Name $currentName }
        finally { $script:WtwCmuxApplyingFromInit = $false }
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
        # stays as the bare pretty name for the sidebar/switcher. Invoke via the
        # pre-captured command so it survives the Restore-WtwInstalledModule re-import.
        $tabLabel = if ($getTabLabel) { & $getTabLabel -PrettyName $prettyName } else { $prettyName }
        & $invokeRawCommand -CmuxBin $cmuxBin -ArgumentList @('rename-tab', '--workspace', $env:CMUX_WORKSPACE_ID, '--surface', $env:CMUX_SURFACE_ID, $tabLabel) | Out-Null
    }
}
