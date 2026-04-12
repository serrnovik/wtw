# Generate the full VS Code Peacock color customizations block from a base color.
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
