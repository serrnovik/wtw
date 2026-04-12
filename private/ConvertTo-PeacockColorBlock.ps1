<#
.SYNOPSIS
    Builds a VS Code Peacock-style color customizations map from a base color.

.DESCRIPTION
    Derives tab, activity bar, status bar, and title bar colors from BaseColor using
    Lighten-HexColor, ConvertTo-DarkerHexColor, Add-HexAlpha, and Get-ContrastForeground.

.PARAMETER BaseColor
    Hex color for the theme base (e.g., '#RRGGBB').

.EXAMPLE
    ConvertTo-PeacockColorBlock -BaseColor '#2ba7d0'
    Returns an ordered hashtable of VS Code color keys and hex values.

.NOTES
    Depends on: Get-ContrastForeground, Lighten-HexColor, ConvertTo-DarkerHexColor, Add-HexAlpha
#>
function ConvertTo-PeacockColorBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $BaseColor
    )

    $base = $BaseColor
    $fg = Get-ContrastForeground $base
    $lighter = Lighten-HexColor $base -Factor 0.25
    $darker = ConvertTo-DarkerHexColor $base -Factor 0.15
    $complementHue = Lighten-HexColor (ConvertTo-DarkerHexColor $base -Factor 0.3) -Factor 0.1

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
