# Darken a hex color by a factor (0.0–1.0).
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
