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
        # Nothing assigned at all — pick randomly from palette
        $cands = @($Colors.palette)
        return $cands | Get-Random
    }

    # Use assigned colors + excluded color as repulsion points
    # (excluded color: we want distance from it so "random" gives something visibly different)
    $repulsionSet = @($assigned)
    if ($excludedColor) { $repulsionSet += $excludedColor }
    # Use a loop instead of pipeline to avoid array unrolling
    $assignedRgb = @()
    foreach ($hex in $repulsionSet) { $assignedRgb += , (ConvertTo-WtwRgbArray $hex) }

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
    $scored = @()

    foreach ($c in $candidates) {
        $rgb = ConvertTo-WtwRgbArray $c
        $minDist = [double]::MaxValue
        foreach ($a in $assignedRgb) {
            $d = Get-PerceptualDistance $rgb $a
            if ($d -lt $minDist) { $minDist = $d }
        }
        $scored += @{ Color = $c; Score = $minDist }
    }

    # Sort descending by score
    $scored = $scored | Sort-Object Score -Descending

    # Take top 15 and pick one at random
    $poolSize = [math]::Min(15, $scored.Count)
    if ($poolSize -gt 0) {
        $pool = $scored[0..($poolSize - 1)]
        $picked = $pool | Get-Random
        return $picked.Color
    }

    return $null
}
