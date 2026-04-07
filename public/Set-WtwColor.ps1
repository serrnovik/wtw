function Set-WtwColor {
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

function Find-WtwContrastColor {
    <#
    .SYNOPSIS
        Pick a color maximally distant from all currently assigned colors.
    #>
    param(
        [PSObject] $Colors,
        [string] $ExcludeKey  # Don't count this key's current color as "in use"
    )

    # Collect assigned colors, remembering the excluded key's current color
    $assigned = @()
    $excludedColor = $null
    foreach ($prop in $Colors.assignments.PSObject.Properties) {
        if ($ExcludeKey -and $prop.Name -eq $ExcludeKey) {
            $excludedColor = $prop.Value
            continue
        }
        $assigned += $prop.Value
    }

    if ($assigned.Count -eq 0 -and -not $excludedColor) {
        # Nothing assigned at all — pick first from palette
        return @($Colors.palette)[0]
    }

    # Use assigned colors + excluded color as repulsion points
    # (excluded color: we want distance from it so "random" gives something visibly different)
    $repulsionSet = @($assigned)
    if ($excludedColor) { $repulsionSet += $excludedColor }
    # Use a loop instead of pipeline to avoid array unrolling
    $assignedRgb = @()
    foreach ($hex in $repulsionSet) { $assignedRgb += , (Convert-HexToRgb $hex) }

    # Candidates: full palette + generated hue samples for broader coverage
    $candidates = @()
    foreach ($c in @($Colors.palette)) { $candidates += $c }

    # Generate 72 evenly-spaced hues at two saturation/lightness levels
    for ($h = 0; $h -lt 360; $h += 5) {
        $candidates += Convert-HslToHex $h 0.75 0.45
        $candidates += Convert-HslToHex $h 0.90 0.55
    }

    # Remove the excluded key's current color from candidates so "random" always gives a new color
    if ($excludedColor) {
        $excludedLower = $excludedColor.ToLower()
        $candidates = $candidates | Where-Object { $_.ToLower() -ne $excludedLower }
    }

    # Score each candidate: minimum perceptual distance to any assigned color
    $best = $null
    $bestScore = -1

    foreach ($c in $candidates) {
        $rgb = Convert-HexToRgb $c
        $minDist = [double]::MaxValue
        foreach ($a in $assignedRgb) {
            $d = Get-PerceptualDistance $rgb $a
            if ($d -lt $minDist) { $minDist = $d }
        }
        if ($minDist -gt $bestScore) {
            $bestScore = $minDist
            $best = $c
        }
    }

    return $best
}

function Convert-HexToRgb {
    param([string] $Hex)
    $Hex = $Hex.TrimStart('#')
    return @(
        [convert]::ToInt32($Hex.Substring(0, 2), 16),
        [convert]::ToInt32($Hex.Substring(2, 2), 16),
        [convert]::ToInt32($Hex.Substring(4, 2), 16)
    )
}

function Get-PerceptualDistance {
    <#
    .SYNOPSIS
        Weighted Euclidean distance in RGB — approximates human perception.
        Based on the "redmean" formula from compuphase.
    #>
    param([int[]] $A, [int[]] $B)
    $rmean = ($A[0] + $B[0]) / 2.0
    $dr = $A[0] - $B[0]
    $dg = $A[1] - $B[1]
    $db = $A[2] - $B[2]
    return [math]::Sqrt(
        (2 + $rmean / 256.0) * $dr * $dr +
        4 * $dg * $dg +
        (2 + (255 - $rmean) / 256.0) * $db * $db
    )
}

function Convert-HslToHex {
    param([double] $H, [double] $S, [double] $L)

    $c = (1 - [math]::Abs(2 * $L - 1)) * $S
    $x = $c * (1 - [math]::Abs(($H / 60) % 2 - 1))
    $m = $L - $c / 2

    $r1 = 0; $g1 = 0; $b1 = 0
    if ($H -lt 60) { $r1 = $c; $g1 = $x; $b1 = 0 }
    elseif ($H -lt 120) { $r1 = $x; $g1 = $c; $b1 = 0 }
    elseif ($H -lt 180) { $r1 = 0; $g1 = $c; $b1 = $x }
    elseif ($H -lt 240) { $r1 = 0; $g1 = $x; $b1 = $c }
    elseif ($H -lt 300) { $r1 = $x; $g1 = 0; $b1 = $c }
    else { $r1 = $c; $g1 = 0; $b1 = $x }

    $r = [int](($r1 + $m) * 255)
    $g = [int](($g1 + $m) * 255)
    $b = [int](($b1 + $m) * 255)

    return "#$(ConvertTo-HexComponent $r)$(ConvertTo-HexComponent $g)$(ConvertTo-HexComponent $b)"
}

function Write-WtwColorSwatch {
    <#
    .SYNOPSIS
        Print a label, hex value, and a colored block swatch using ANSI true-color.
    #>
    param(
        [string] $Label,
        [string] $Hex
    )
    $h = $Hex.TrimStart('#')
    $r = [convert]::ToInt32($h.Substring(0, 2), 16)
    $g = [convert]::ToInt32($h.Substring(2, 2), 16)
    $b = [convert]::ToInt32($h.Substring(4, 2), 16)
    $swatch = "`e[48;2;${r};${g};${b}m    `e[0m"   # 4-char block with background color
    Write-Host "${Label} = ${Hex} ${swatch}"
}
