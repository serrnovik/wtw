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

    # Capture private helpers before any session work. Enter-WtwWorktree's
    # Restore-WtwInstalledModule does a -Force re-import, which invalidates
    # by-name resolution of module-private functions for this stack frame.
    $getTabLabel = Get-Command Get-WtwCmuxTabLabel -ErrorAction SilentlyContinue
    $setOverride = Get-Command Set-WtwCmuxTabTitleOverride -ErrorAction SilentlyContinue
    $setTabLabel = Get-Command Set-WtwCmuxCurrentTabLabel -ErrorAction SilentlyContinue
    $invokeRawCommand = Get-Command Invoke-WtwCmuxRawCommand -ErrorAction SilentlyContinue
    $cmuxBin = Get-WtwCmuxBin

    $remote = Get-WtwCmuxCurrentRemoteSession
    if ($remote) {
        $prettyName = Get-WtwCmuxRemoteSessionPrettyName -Remote $remote
        if ($setTabLabel) {
            & $setTabLabel `
                -PrettyName $prettyName `
                -GetTabLabel $getTabLabel `
                -SetOverride $setOverride `
                -InvokeRawCommand $invokeRawCommand `
                -CmuxBin $cmuxBin
        } elseif ($prettyName -and $env:CMUX_WORKSPACE_ID -and $env:CMUX_SURFACE_ID) {
            # After Restore-WtwInstalledModule, Get-Command / by-name lookup of
            # private helpers can miss. Pin the override with the same path
            # formula Set-WtwCmuxTabTitleOverride uses.
            $icon = if ($env:WTW_TAB_ICON) { $env:WTW_TAB_ICON } else { '🖥️🌳' }
            $tabLabel = if ($getTabLabel) {
                & $getTabLabel -PrettyName $prettyName
            } else {
                "$icon $($prettyName.Trim())".Trim()
            }
            if ($setOverride) {
                & $setOverride -WorkspaceId $env:CMUX_WORKSPACE_ID -SurfaceId $env:CMUX_SURFACE_ID -Title $tabLabel | Out-Null
            } else {
                $safe = ($env:CMUX_WORKSPACE_ID + '.' + $env:CMUX_SURFACE_ID) -replace '[^\w.-]', '_'
                $path = Join-Path ([System.IO.Path]::GetTempPath()) "wtw-cmux-tab-$safe"
                Set-Content -LiteralPath $path -Value $tabLabel -Encoding utf8 -NoNewline
            }
            if ($invokeRawCommand) {
                & $invokeRawCommand -CmuxBin $cmuxBin -ArgumentList @(
                    'rename-tab',
                    '--workspace', $env:CMUX_WORKSPACE_ID,
                    '--surface', $env:CMUX_SURFACE_ID,
                    $tabLabel
                ) | Out-Null
            }
        }
        if ($ApplyTerminalSession) {
            Connect-WtwRemoteWorktree -HostEntry $remote.HostEntry -Name $remote.Name
        }
        return
    }

    if (-not $env:CMUX_WORKSPACE_ID) { return }

    $currentName = Resolve-WtwCurrentTarget
    if (-not $currentName) { return }

    $target = & { Resolve-WtwTarget $currentName } 6>$null
    if (-not $target) { return }

    $metadata = Resolve-WtwTerminalWorkspaceMetadata -Target $target
    if (-not ($metadata -and $metadata.Path -and (Test-Path $metadata.Path))) { return }

    $prettyName = $metadata.PrettyName
    $color = $metadata.Color
    $statusValue = $metadata.StatusValue

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
    if ($env:CMUX_SURFACE_ID -and $prettyName -and $setTabLabel) {
        # Tab label gets the console+tree wtw icon prefix; the workspace title (above)
        # stays as the bare pretty name for the sidebar/switcher. Also pin the label
        # so agent-action.ps1's title guard cannot stomp it back to 🌴 wtw.
        & $setTabLabel `
            -PrettyName $prettyName `
            -GetTabLabel $getTabLabel `
            -SetOverride $setOverride `
            -InvokeRawCommand $invokeRawCommand `
            -CmuxBin $cmuxBin
    }
}
