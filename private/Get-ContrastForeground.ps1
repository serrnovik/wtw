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
