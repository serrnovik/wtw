<#
.SYNOPSIS
    Picks a readable foreground color for a given background.

.DESCRIPTION
    Uses the WCAG 2.x relative-luminance and contrast-ratio formulas rather than
    a perceived-brightness threshold.

    The old version compared YIQ brightness against 0.5 and returned near-black
    or near-white. That splits colors into two buckets but never checks the
    result is actually readable, so mid-tone palette entries — the oranges,
    teals and mid greens that sit either side of the threshold — produced
    title-bar and active-tab text hovering around 3:1, which reads as washed out
    in both light and dark editor themes.

    Now both candidates are scored and the better one wins. If even the winner
    falls under the WCAG AA threshold for large text (4.5:1 is the body-text
    bar; chrome text is large/bold, so 4.5 is used here as a conservative
    target), it escalates to pure white or pure black, which is the most
    contrast a single foreground can give against that background.

.PARAMETER Hex
    Background color as '#RRGGBB' or 'RRGGBB'.

.EXAMPLE
    Get-ContrastForeground '#e05d44'
    Returns the darker or lighter foreground, whichever reads better.

.NOTES
    Depends on: nothing.
#>
function Get-WtwRelativeLuminance {
    <#
    .SYNOPSIS
        WCAG relative luminance (0..1) for an sRGB hex color.
    .DESCRIPTION
        Applies the sRGB gamma expansion the spec requires. A plain weighted
        average of the raw channel bytes — which is what "perceived brightness"
        formulas use — is not the same curve and misjudges saturated colors.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Hex)

    $clean = $Hex.TrimStart('#')
    $channels = @(
        [convert]::ToInt32($clean.Substring(0, 2), 16)
        [convert]::ToInt32($clean.Substring(2, 2), 16)
        [convert]::ToInt32($clean.Substring(4, 2), 16)
    )

    $linear = foreach ($channel in $channels) {
        $srgb = $channel / 255
        if ($srgb -le 0.03928) { $srgb / 12.92 } else { [Math]::Pow((($srgb + 0.055) / 1.055), 2.4) }
    }

    return (0.2126 * $linear[0]) + (0.7152 * $linear[1]) + (0.0722 * $linear[2])
}

function Get-WtwContrastRatio {
    <#
    .SYNOPSIS
        WCAG contrast ratio between two hex colors (1.0 .. 21.0).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Foreground,
        [Parameter(Mandatory)] [string] $Background
    )

    $l1 = Get-WtwRelativeLuminance -Hex $Foreground
    $l2 = Get-WtwRelativeLuminance -Hex $Background
    $lighter = [Math]::Max($l1, $l2)
    $darker = [Math]::Min($l1, $l2)
    return (($lighter + 0.05) / ($darker + 0.05))
}

function Get-ContrastForeground {
    [CmdletBinding()]
    param([string] $Hex)

    $background = if ($Hex.StartsWith('#')) { $Hex } else { "#$Hex" }

    # Softened near-black / near-white first: they sit better against a colored
    # chrome than pure values, so they are preferred whenever they are readable.
    $dark = '#15202b'
    $light = '#e7e7e7'

    $darkRatio = Get-WtwContrastRatio -Foreground $dark -Background $background
    $lightRatio = Get-WtwContrastRatio -Foreground $light -Background $background

    $best = if ($darkRatio -ge $lightRatio) { $dark } else { $light }
    $bestRatio = [Math]::Max($darkRatio, $lightRatio)

    if ($bestRatio -ge 4.5) { return $best }

    # Mid-tone background: neither softened value is readable, so take the
    # maximum available contrast instead of returning something washed out.
    $blackRatio = Get-WtwContrastRatio -Foreground '#000000' -Background $background
    $whiteRatio = Get-WtwContrastRatio -Foreground '#ffffff' -Background $background
    return $(if ($blackRatio -ge $whiteRatio) { '#000000' } else { '#ffffff' })
}
