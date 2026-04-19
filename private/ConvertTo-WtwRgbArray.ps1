function ConvertTo-WtwRgbArray {
    param([string] $Hex)
    $Hex = $Hex.TrimStart('#')
    return @(
        [convert]::ToInt32($Hex.Substring(0, 2), 16),
        [convert]::ToInt32($Hex.Substring(2, 2), 16),
        [convert]::ToInt32($Hex.Substring(4, 2), 16)
    )
}
