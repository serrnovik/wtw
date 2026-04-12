<#
.SYNOPSIS
    Returns a light or dark foreground hex color for contrast against a background.

.DESCRIPTION
    Computes relative luminance from the RGB hex and returns '#15202b' or '#e7e7e7'
    for readable contrast. Expects a six-digit hex after optional '#'.

.PARAMETER Hex
    Background color as '#RRGGBB' or 'RRGGBB'.

.EXAMPLE
    Get-ContrastForeground -Hex '#ffffff'
    Returns '#15202b' for dark text on a light background.

.NOTES
    No external dependencies.
#>
function Get-ContrastForeground {
    param([string] $Hex)
    $Hex = $Hex.TrimStart('#')
    $r = [convert]::ToInt32($Hex.Substring(0, 2), 16)
    $g = [convert]::ToInt32($Hex.Substring(2, 2), 16)
    $b = [convert]::ToInt32($Hex.Substring(4, 2), 16)
    # Relative luminance
    $lum = (0.299 * $r + 0.587 * $g + 0.114 * $b) / 255
    if ($lum -gt 0.5) { return '#15202b' } else { return '#e7e7e7' }
}
