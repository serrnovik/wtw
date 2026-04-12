<#
.SYNOPSIS
    Lightens a hex color by blending toward white.

.DESCRIPTION
    Increases each RGB component toward 255 by the specified factor.
    Requires ConvertTo-HexComponent.

.PARAMETER Hex
    The hex color to lighten (e.g., '#RRGGBB' or 'RRGGBB').

.PARAMETER Factor
    Blend factor between 0.0 and 1.0; higher values produce lighter colors.
    Default is 0.2.

.EXAMPLE
    Lighten-HexColor -Hex '#FF5733' -Factor 0.25
    Returns a hex color blended 25% toward white.

.NOTES
    Depends on: ConvertTo-HexComponent
#>
function Lighten-HexColor {
    param(
        [string] $Hex,
        [double] $Factor = 0.2
    )
    $Hex = $Hex.TrimStart('#')
    $r = [convert]::ToInt32($Hex.Substring(0, 2), 16)
    $g = [convert]::ToInt32($Hex.Substring(2, 2), 16)
    $b = [convert]::ToInt32($Hex.Substring(4, 2), 16)

    $r = [int]($r + (255 - $r) * $Factor)
    $g = [int]($g + (255 - $g) * $Factor)
    $b = [int]($b + (255 - $b) * $Factor)

    return "#$(ConvertTo-HexComponent $r)$(ConvertTo-HexComponent $g)$(ConvertTo-HexComponent $b)"
}
