# Append a hex alpha channel suffix to a color string.
function Add-HexAlpha {
    param(
        [string] $Hex,
        [string] $Alpha = '99'
    )
    return "$Hex$Alpha"
}
