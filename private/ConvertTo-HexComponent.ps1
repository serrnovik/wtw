# Clamp an integer to 0–255 and convert to a two-digit hex string.
function ConvertTo-HexComponent {
    param([int] $Value)
    return ([math]::Max(0, [math]::Min(255, $Value))).ToString('x2')
}
