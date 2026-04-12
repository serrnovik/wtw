<#
.SYNOPSIS
    Appends a hex alpha suffix to a color string.

.DESCRIPTION
    Concatenates the hex color with a two-character alpha channel suffix (default '99').

.PARAMETER Hex
    Base hex color string (typically '#RRGGBB' or 'RRGGBB' without validation here).

.PARAMETER Alpha
    Two hex digits for alpha (00-FF). Default is '99'.

.EXAMPLE
    Add-HexAlpha -Hex '#1a2b3c' -Alpha '80'
    Returns '#1a2b3c80'.

.NOTES
    No external dependencies. Does not validate hex format.
#>
function Add-HexAlpha {
    param(
        [string] $Hex,
        [string] $Alpha = '99'
    )
    return "$Hex$Alpha"
}
