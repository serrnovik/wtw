<#
.SYNOPSIS
    Builds a VS Code Peacock-style color customizations map from a base color.

.DESCRIPTION
    Derives tab, activity bar, status bar, and title bar colors from BaseColor using
    Lighten-HexColor, ConvertTo-DarkerHexColor, Add-HexAlpha, and Get-ContrastForeground.

    The map covers every key the Peacock extension also writes. That is deliberate:
    Peacock merges over whatever it finds, so any key wtw leaves unset is a key Peacock
    fills in with its own value. In Cursor specifically it hard-codes
    `titleBar.activeForeground` and `commandCenter.foreground` to #595959 regardless of
    the background — mid-grey on a saturated title bar, which is the unreadable window
    title. New-WtwWorkspaceFile keeps Peacock dormant by never writing a `peacock.*`
    setting; owning the full key set here is the second half of that, so a workspace
    stays readable even if Peacock is provoked by something else.

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
    # The activity bar is painted with $lighter, not $base, so it needs its own
    # contrast decision — reusing $base's foreground is how icons end up washed out
    # on the pastel end of the palette.
    $lighterFg = Get-ContrastForeground $lighter
    $darker = ConvertTo-DarkerHexColor $base -Factor 0.15
    $complementHue = Lighten-HexColor (ConvertTo-DarkerHexColor $base -Factor 0.3) -Factor 0.1

    return [ordered]@{
        'tab.activeBackground'            = $base
        'tab.activeForeground'            = $fg
        'tab.activeBorderTop'             = $lighter
        # A hard underline in the foreground color. The active tab used to be
        # identifiable only by its fill, which is the same hue as the title bar
        # above it — so "which file am I in" was a low-contrast judgement in both
        # light and dark themes. The border reads regardless of theme.
        'tab.activeBorder'                = $fg
        # Keep the current file identifiable when focus moves to a terminal or
        # the sidebar; VS Code otherwise dims the active tab to near-invisible.
        'tab.unfocusedActiveBackground'   = $base
        'tab.unfocusedActiveForeground'   = (Add-HexAlpha $fg 'cc')
        'tab.unfocusedActiveBorderTop'    = $lighter
        'activityBar.background'          = $lighter
        'activityBar.foreground'          = $lighterFg
        'activityBar.activeBackground'    = $lighter
        # 'cc' (80%) rather than '99' (60%): these sit on the colored chrome, and
        # 60% of an already-mid-contrast foreground is what made them fade out.
        'activityBar.inactiveForeground'  = (Add-HexAlpha $lighterFg 'cc')
        # Cursor renders the activity bar horizontally under the title bar, which
        # is a different set of color keys than the vertical one.
        'activityBarTop.background'       = $lighter
        'activityBarTop.foreground'       = $lighterFg
        'activityBarTop.activeBackground' = $lighter
        'activityBarTop.inactiveForeground' = (Add-HexAlpha $lighterFg 'cc')
        'activityBarBadge.background'     = $complementHue
        'activityBarBadge.foreground'     = (Get-ContrastForeground $complementHue)
        'commandCenter.border'            = (Add-HexAlpha $fg 'cc')
        # The command center is the pill that holds the window title in Cursor and
        # in VS Code's custom title bar, so all three of its foregrounds have to
        # clear the same contrast bar as the title bar itself.
        'commandCenter.foreground'        = $fg
        'commandCenter.activeForeground'  = $fg
        'commandCenter.inactiveForeground' = $fg
        'sash.hoverBorder'                = $lighter
        'statusBar.background'            = $base
        'statusBar.foreground'            = $fg
        'statusBar.debuggingBackground'   = $base
        'statusBar.debuggingForeground'   = $fg
        'statusBarItem.hoverBackground'   = $lighter
        'statusBarItem.remoteBackground'  = $base
        'statusBarItem.remoteForeground'  = $fg
        'titleBar.activeBackground'       = $base
        'titleBar.activeForeground'       = $fg
        'titleBar.inactiveBackground'     = (Add-HexAlpha $base)
        # The window title over the colored bar: 60% alpha put it below the
        # readability line on mid-tone colors, which is the "titles over main
        # color panels" complaint.
        'titleBar.inactiveForeground'     = (Add-HexAlpha $fg 'cc')
    }
}
