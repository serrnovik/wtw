function ConvertTo-HexComponent {
    param([int] $Value)
    return ([math]::Max(0, [math]::Min(255, $Value))).ToString('x2')
}

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

function Darken-HexColor {
    param(
        [string] $Hex,
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

function Add-HexAlpha {
    param(
        [string] $Hex,
        [string] $Alpha = '99'
    )
    return "$Hex$Alpha"
}

function ConvertTo-PeacockColorBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $BaseColor
    )

    $base = $BaseColor
    $fg = Get-ContrastForeground $base
    $lighter = Lighten-HexColor $base -Factor 0.25
    $darker = Darken-HexColor $base -Factor 0.15
    $complementHue = Lighten-HexColor (Darken-HexColor $base -Factor 0.3) -Factor 0.1

    return [ordered]@{
        'tab.activeBackground'            = $base
        'tab.activeForeground'            = $fg
        'tab.activeBorderTop'             = $lighter
        'activityBar.activeBackground'    = $lighter
        'activityBar.inactiveForeground'  = "${fg}99"
        'activityBarBadge.background'     = $complementHue
        'activityBarBadge.foreground'     = $fg
        'commandCenter.border'            = "${fg}99"
        'sash.hoverBorder'                = $lighter
        'statusBarItem.hoverBackground'   = $lighter
        'statusBarItem.remoteBackground'  = $base
        'statusBarItem.remoteForeground'  = $fg
        'titleBar.activeBackground'       = $base
        'titleBar.activeForeground'       = $fg
        'titleBar.inactiveBackground'     = (Add-HexAlpha $base)
        'titleBar.inactiveForeground'     = (Add-HexAlpha $fg)
    }
}
