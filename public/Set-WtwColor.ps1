function Set-WtwColor {
    <#
    .SYNOPSIS
        Set or display the Peacock color for a workspace.
    .DESCRIPTION
        Assigns a hex color or auto-selects a maximum-contrast color for a workspace.
        When called without a Color argument, displays the current color assignment.
        Updates both colors.json and the registry, then syncs the workspace file
        unless --no-sync is specified.
    .PARAMETER Name
        Target workspace or repo name. Defaults to the current working directory.
    .PARAMETER Color
        Hex color (e.g. '#689b59' or 689b59) or 'random' for automatic contrast selection.
    .PARAMETER NoSync
        Skip re-syncing the workspace file after the color change.
    .EXAMPLE
        wtw color auth random
        Assigns a maximum-contrast color to the "auth" workspace.
    .EXAMPLE
        wtw color auth '#689b59'
        Sets the "auth" workspace color to the specified hex value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Name,

        [Parameter(Position = 1)]
        [string] $Color,

        [Alias('ns')]
        [switch] $NoSync
    )

    # Allow `wtw color random` or `wtw color #689b59` without an explicit name
    if ($Name -and -not $Color -and ($Name -eq 'random' -or $Name -match '^#?[0-9a-fA-F]{6}$')) {
        $Color = $Name
        $Name = $null
    }

    # Detect from cwd if no name given
    $nameFromCwd = -not $Name
    if (-not $Name) {
        $Name = Resolve-WtwCurrentTarget
        if (-not $Name) {
            Write-Error "Not inside a registered repo. Specify a target or cd into a repo."
            return
        }
        Write-Host "  Detected: $Name" -ForegroundColor DarkGray
    }

    $target = Resolve-WtwTarget $Name
    if (-not $target) { return }

    $colorKey = if ($target.TaskName) { "$($target.RepoName)/$($target.TaskName)" } else { "$($target.RepoName)/main" }
    $colors = Get-WtwColors

    # Show current color if no color arg
    if (-not $Color) {
        $current = $null
        if ($colors.assignments.PSObject.Properties.Name -contains $colorKey) {
            $current = $colors.assignments.$colorKey
        }
        if ($current) {
            Write-Host ''
            Write-WtwColorSwatch "  $colorKey" $current
            Write-Host "  Tip: in PowerShell, '#rrggbb' must be quoted. Use 689b59 or '#689b59'." -ForegroundColor DarkGray
            Write-Host ''
        } else {
            Write-Host "  No color assigned for $colorKey" -ForegroundColor DarkGray
            Write-Host "  Tip: in PowerShell, '#rrggbb' must be quoted. Use 689b59 or '#689b59'." -ForegroundColor DarkGray
        }
        return
    }

    # Resolve color — hex, 'random', or a named color from the bundled palette
    $newColor = Resolve-WtwColorInput -Color $Color -ExcludeKey $colorKey
    if (-not $newColor) {
        Write-Error "Invalid color '$Color'. Use '#rrggbb', 'random', or a known color name."
        return
    }
    if ($Color -ieq 'random') { Write-Host "  Picked: $newColor" -ForegroundColor DarkGray }

    # Save to colors.json
    $colors.assignments | Add-Member -NotePropertyName $colorKey -NotePropertyValue $newColor -Force
    Save-WtwColors $colors

    # Also update registry worktree entry if applicable
    if ($target.WorktreeEntry) {
        $target.WorktreeEntry | Add-Member -NotePropertyName 'color' -NotePropertyValue $newColor -Force
        $registry = Get-WtwRegistry
        $registry.repos.$($target.RepoName).worktrees.$($target.TaskName) = $target.WorktreeEntry
        Save-WtwRegistry $registry

        # Keep SourceGit's bookmark in sync with the new color
        Add-WtwSourceGitRepository -Path $target.WorktreeEntry.path `
            -Name ($target.WorktreeEntry.prettyName ?? "$($target.RepoName)/$($target.TaskName)") `
            -Hex $newColor
    }

    Write-Host ''
    Write-WtwColorSwatch "  $colorKey" $newColor

    # Sync workspace unless --no-sync
    if (-not $NoSync) {
        $wsFile = $null
        if ($target.WorktreeEntry) {
            $wsFile = $target.WorktreeEntry.workspace
        } else {
            $wsFile = $target.RepoEntry.templateWorkspace
        }

        if ($wsFile -and (Test-Path $wsFile)) {
            Write-Host "  Syncing workspace..." -ForegroundColor DarkGray
            Sync-WtwWorkspace -Target $wsFile -ColorSource Json
        } else {
            Write-Host "  No workspace file to sync." -ForegroundColor DarkGray
        }
    }

    # Apply color to the current terminal tab immediately if this target is active here
    $applyNow = $nameFromCwd
    if (-not $applyNow) {
        $currentName = Resolve-WtwCurrentTarget
        if ($currentName) {
            $currentTarget = Resolve-WtwTarget $currentName
            if ($currentTarget) {
                $currentKey = if ($currentTarget.TaskName) { "$($currentTarget.RepoName)/$($currentTarget.TaskName)" } else { "$($currentTarget.RepoName)/main" }
                $applyNow = $currentKey -eq $colorKey
            }
        }
    }
    if ($applyNow) {
        Set-WtwTerminalColor -Color $newColor
        # Windows Terminal cannot repaint a tab from inside it. Tell the user
        # how to actually see the new color.
        if ($IsWindows -and $env:WT_SESSION) {
            $alias = $colorKey -replace '/main$', '' -replace '/', '-'
            Write-Host "  Windows Terminal can't recolor this tab in place." -ForegroundColor DarkYellow
            Write-Host "  Spawn a new tab to see it:  wtw go $alias --new-tab" -ForegroundColor Cyan
        }
    }

    Write-Host ''
}


