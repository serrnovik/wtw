function Find-WtwContrastColor {
    <#
    .SYNOPSIS
        Pick a color that is visibly different from other assignments, with hue
        variety (not clustered in teal/cyan).
    .DESCRIPTION
        Builds a candidate set from the palette plus 15 evenly spaced vivid hues
        and supplemental HSL samples. Filters by minimum perceptual distance to
        repulsion points (other assignments + current color when re-rolling).
        Stratifies survivors by hue into 15 bins and picks uniformly at random
        among the best candidate per bin — so `wtw color random` cycles through
        reds, oranges, purples, etc., not only blue-green.
    #>
    param(
        [PSObject] $Colors,
        [string] $ExcludeKey
    )

    function Get-WtwHueBin {
        param(
            [string] $Hex,
            [int] $BinCount
        )
        $rgb = ConvertTo-WtwRgbArray $Hex
        $r = $rgb[0] / 255.0
        $g = $rgb[1] / 255.0
        $b = $rgb[2] / 255.0
        $max = [math]::Max($r, [math]::Max($g, $b))
        $min = [math]::Min($r, [math]::Min($g, $b))
        $d = $max - $min
        $h = 0.0
        if ($d -ge 1e-9) {
            if ([math]::Abs($max - $r) -lt 1e-9) {
                $h = ((60 * (($g - $b) / $d)) + 360) % 360
            } elseif ([math]::Abs($max - $g) -lt 1e-9) {
                $h = (60 * (($b - $r) / $d) + 120) % 360
            } else {
                $h = (60 * (($r - $g) / $d) + 240) % 360
            }
        }
        $w = 360.0 / $BinCount
        return [int]([math]::Floor($h / $w)) % $BinCount
    }

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
        $cands = @($Colors.palette)
        return $cands | Get-Random
    }

    $repulsionSet = @($assigned)
    if ($excludedColor) { $repulsionSet += $excludedColor }
    $assignedRgb = @()
    foreach ($hex in $repulsionSet) { $assignedRgb += , (ConvertTo-WtwRgbArray $hex) }

    $hueSlots = 15
    $step = 360.0 / $hueSlots

    # Dedupe candidates (case-insensitive hex)
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $candidates = [System.Collections.Generic.List[string]]::new()

    foreach ($c in @($Colors.palette)) {
        if ($seen.Add($c)) { $candidates.Add($c) }
    }

    # 15 vivid, evenly spaced hues — guarantees red/orange/yellow/... not only cyan
    for ($i = 0; $i -lt $hueSlots; $i++) {
        $hx = Convert-HslToHex ($i * $step) 0.78 0.47
        if ($seen.Add($hx)) { $candidates.Add($hx) }
    }

    # Mid-step hues + second saturation/lightness ring for extra separation options
    for ($i = 0; $i -lt $hueSlots; $i++) {
        $hx = Convert-HslToHex (($i * $step) + ($step / 2)) 0.72 0.52
        if ($seen.Add($hx)) { $candidates.Add($hx) }
    }

    for ($h = 0; $h -lt 360; $h += 10) {
        $hx = Convert-HslToHex $h 0.70 0.46
        if ($seen.Add($hx)) { $candidates.Add($hx) }
    }

    if ($excludedColor) {
        $exLower = $excludedColor.ToLower()
        $filteredList = [System.Collections.Generic.List[string]]::new()
        foreach ($cx in $candidates) {
            if ($cx.ToLower() -ne $exLower) { $filteredList.Add($cx) }
        }
        $candidates = $filteredList
    }

    function Get-MinDist {
        param([int[]] $Rgb)
        $minDist = [double]::MaxValue
        foreach ($a in $assignedRgb) {
            $d = Get-PerceptualDistance $Rgb $a
            if ($d -lt $minDist) { $minDist = $d }
        }
        return $minDist
    }

    function Build-StratifiedPool {
        param(
            [double] $MinSep
        )
        $scored = @()
        foreach ($c in $candidates) {
            $rgb = ConvertTo-WtwRgbArray $c
            $minDist = Get-MinDist $rgb
            if ($minDist -ge $MinSep) {
                $scored += @{ Color = $c; Score = $minDist; Bin = (Get-WtwHueBin $c $hueSlots) }
            }
        }
        if ($scored.Count -eq 0) { return @() }

        $byBin = @{}
        foreach ($row in $scored) {
            $b = $row.Bin
            if (-not $byBin.ContainsKey($b) -or $row.Score -gt $byBin[$b].Score) {
                $byBin[$b] = $row
            }
        }
        return @($byBin.Values | ForEach-Object { $_.Color })
    }

    foreach ($trySep in @(58, 45, 32, 20, 0)) {
        $pool = Build-StratifiedPool -MinSep $trySep
        if ($pool.Count -gt 0) {
            return $pool | Get-Random
        }
    }

    # Last resort: any candidate with best min-distance, no stratification
    $best = @()
    $bestScore = -1.0
    foreach ($c in $candidates) {
        $rgb = ConvertTo-WtwRgbArray $c
        $s = Get-MinDist $rgb
        if ($s -gt $bestScore) {
            $bestScore = $s
            $best = @($c)
        } elseif ([math]::Abs($s - $bestScore) -lt 1e-6) {
            $best += $c
        }
    }
    if ($best.Count -gt 0) {
        return $best | Get-Random
    }

    return $null
}
