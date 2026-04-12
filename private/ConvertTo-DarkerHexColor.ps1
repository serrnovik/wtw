<#
.SYNOPSIS
    Darkens a hex color by a specified factor.

.DESCRIPTION
    Converts a hex color to a darker shade by reducing RGB component values
    by the specified factor. Requires ConvertTo-HexComponent.

.PARAMETER Hex
    The hex color to darken (e.g., '#RRGGBB' or 'RRGGBB').

.PARAMETER Factor
    The darkening factor between 0.0 and 1.0, where higher values produce darker colors.
    Default is 0.2.

.EXAMPLE
    ConvertTo-DarkerHexColor -Hex '#FF5733' -Factor 0.3
    Returns a hex color 30% darker than the input.

.NOTES
    Depends on: ConvertTo-HexComponent
#>
function ConvertTo-DarkerHexColor {
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^#?[0-9A-Fa-f]{6}$')]
        [string] $Hex,
        [ValidateRange(0.0, 1.0)]
        [double] $Factor = 0.2
    )
    $Hex = $Hex.TrimStart('#')
    $r = [convert]::ToInt32($Hex.Substring(0, 2), 16)
    $g = [convert]::ToInt32($Hex.Substring(2, 2), 16)
    $b = [convert]::ToInt32($Hex.Substring(4, 2), 16)

    $r = [int]($r * (1 - $Factor))
    $g = [int]($g * (1 - $Factor))
    $b = [int]($b * (1 - $Factor))

    return "#$(ConvertTo-HexComponent $r)$(ConvertTo-HexComponent $g)$(ConvertTo-HexComponent $b)"
}
