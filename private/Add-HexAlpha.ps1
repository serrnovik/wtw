function Add-HexAlpha {
    param(
        [string] $Hex,
        [string] $Alpha = '99'
    )
    return "$Hex$Alpha"
}
