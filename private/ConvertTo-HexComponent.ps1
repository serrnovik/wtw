function ConvertTo-HexComponent {
    param([int] $Value)
    return ([math]::Max(0, [math]::Min(255, $Value))).ToString('x2')
}
