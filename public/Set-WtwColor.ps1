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

    # Detect from cwd if no name given
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

    # Resolve color
    if ($Color -eq 'random') {
        $newColor = Find-WtwContrastColor $colors -ExcludeKey $colorKey
        Write-Host "  Picked: $newColor" -ForegroundColor DarkGray
    } elseif ($Color -match '^#?[0-9a-fA-F]{6}$') {
        $newColor = if ($Color.StartsWith('#')) { $Color } else { "#$Color" }
    } else {
        Write-Error "Invalid color '$Color'. Use '#rrggbb' or 'random'."
        return
    }

    # Save to colors.json
    $colors.assignments | Add-Member -NotePropertyName $colorKey -NotePropertyValue $newColor -Force
    Save-WtwColors $colors

    # Also update registry worktree entry if applicable
    if ($target.WorktreeEntry) {
        $target.WorktreeEntry | Add-Member -NotePropertyName 'color' -NotePropertyValue $newColor -Force
        $registry = Get-WtwRegistry
        $registry.repos.$($target.RepoName).worktrees.$($target.TaskName) = $target.WorktreeEntry
        Save-WtwRegistry $registry
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
    Write-Host ''
}


