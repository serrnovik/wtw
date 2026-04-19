function Write-WtwColorSwatch {
    <#
    .SYNOPSIS
        Print a label, hex value, and a colored block swatch using ANSI true-color.
    #>
    param(
        [string] $Label,
        [string] $Hex
    )
    $h = $Hex.TrimStart('#')
    $r = [convert]::ToInt32($h.Substring(0, 2), 16)
    $g = [convert]::ToInt32($h.Substring(2, 2), 16)
    $b = [convert]::ToInt32($h.Substring(4, 2), 16)
    $swatch = "`e[48;2;${r};${g};${b}m    `e[0m"   # 4-char block with background color
    Write-Host "${Label} = ${Hex} ${swatch}"
}
