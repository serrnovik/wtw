function Get-WtwColorCircleEmoji {
    <#
    .SYNOPSIS
        Pick the closest Unicode color-circle emoji for a #rrggbb color.
    .DESCRIPTION
        Returns a single-codepoint emoji from the standard color-circle set so
        SourceGit/Superset display reliably without ZWJ/font-composition issues.
        Distance is Euclidean RGB; saturation acts as a tiebreaker between
        gray-leaning candidates (black/white) and chromatic ones.
    #>
    param([string] $Hex)

    if ([string]::IsNullOrWhiteSpace($Hex)) { return [char]::ConvertFromUtf32(0x26AA) }  # ⚪ default
    $clean = $Hex.TrimStart('#')
    if ($clean -notmatch '^[0-9a-fA-F]{6}$') { return [char]::ConvertFromUtf32(0x26AA) }

    $r = [Convert]::ToInt32($clean.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($clean.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($clean.Substring(4, 2), 16)

    # Representative hex for each circle. Codepoints from Unicode Symbols/Geometric Shapes:
    # 🔴 1F534, 🟠 1F7E0, 🟡 1F7E1, 🟢 1F7E2, 🔵 1F535, 🟣 1F7E3, 🟤 1F7E4, ⚫ 26AB, ⚪ 26AA
    $palette = @(
        @{ CP = 0x1F534; R = 0xE0; G = 0x21; B = 0x21 }   # red
        @{ CP = 0x1F7E0; R = 0xF1; G = 0x8C; B = 0x29 }   # orange
        @{ CP = 0x1F7E1; R = 0xF4; G = 0xD0; B = 0x36 }   # yellow
        @{ CP = 0x1F7E2; R = 0x4B; G = 0xA5; B = 0x32 }   # green
        @{ CP = 0x1F535; R = 0x29; G = 0x6E; B = 0xC8 }   # blue
        @{ CP = 0x1F7E3; R = 0x80; G = 0x40; B = 0xB0 }   # purple
        @{ CP = 0x1F7E4; R = 0x8B; G = 0x4F; B = 0x2D }   # brown
        @{ CP = 0x26AB;  R = 0x1F; G = 0x1F; B = 0x1F }   # black
        @{ CP = 0x26AA;  R = 0xEE; G = 0xEE; B = 0xEE }   # white
    )

    # HSV-style saturation = (max - min) / max. Low-sat inputs (near-gray) should snap
    # to black/white instead of the closest chromatic circle, which usually looks wrong.
    $mx = [Math]::Max($r, [Math]::Max($g, $b))
    $mn = [Math]::Min($r, [Math]::Min($g, $b))
    $sat = if ($mx -eq 0) { 0.0 } else { 1.0 - ($mn / $mx) }

    if ($sat -lt 0.15) {
        # Effectively gray — choose black vs white by brightness.
        return $(if ($mx -lt 128) { [char]::ConvertFromUtf32(0x26AB) } else { [char]::ConvertFromUtf32(0x26AA) })
    }

    $bestCp = 0x26AA
    $bestDist = [double]::MaxValue
    foreach ($p in $palette) {
        if ($p.CP -eq 0x26AB -or $p.CP -eq 0x26AA) { continue }  # skip grays for chromatic inputs
        $dr = $r - $p.R; $dg = $g - $p.G; $db = $b - $p.B
        $d = [double]($dr * $dr + $dg * $dg + $db * $db)
        if ($d -lt $bestDist) {
            $bestDist = $d
            $bestCp = $p.CP
        }
    }
    return [char]::ConvertFromUtf32($bestCp)
}

function Format-WtwPrettyNameWithCircle {
    <#
    .SYNOPSIS
        Prepend the color-circle emoji to a pretty name, dedup-safe.
    .DESCRIPTION
        If the name already starts with one of our circle emojis we replace
        it instead of stacking, so repeated renames don't accumulate prefixes.
    #>
    param(
        [Parameter(Mandatory)][string] $Hex,
        [string] $Name
    )

    $circle = Get-WtwColorCircleEmoji -Hex $Hex
    if ([string]::IsNullOrWhiteSpace($Name)) { return $circle }

    $circleCps = @(0x1F534, 0x1F7E0, 0x1F7E1, 0x1F7E2, 0x1F535, 0x1F7E3, 0x1F7E4, 0x26AB, 0x26AA)
    $stripped = $Name
    if ($Name.Length -ge 2) {
        $cp = [Char]::ConvertToUtf32($Name, 0)
        if ($circleCps -contains $cp) {
            # surrogate pair (1F5xx / 1F7xx range) → 2 chars; symbols (26AB / 26AA) → 1 char
            $skip = if ($cp -gt 0xFFFF) { 2 } else { 1 }
            $stripped = $Name.Substring($skip).TrimStart()
        }
    }
    return "$circle $stripped"
}
