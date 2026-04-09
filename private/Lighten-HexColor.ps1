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
