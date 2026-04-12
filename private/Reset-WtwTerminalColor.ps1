<#
.SYNOPSIS
    Resets terminal tab color styling to the default.

.DESCRIPTION
    Sends reset sequences for tmux, iTerm2, Windows Terminal, Kitty, Konsole, or WezTerm
    when detected. Side effect: writes escape codes to the host output stream.

.EXAMPLE
    Reset-WtwTerminalColor

.NOTES
    Pairs with Set-WtwTerminalColor; same environment detection logic.
#>
function Reset-WtwTerminalColor {
    [CmdletBinding()]
    param()

    $esc = [char]27
    $bel = [char]7
    $inTmux = $null -ne $env:TMUX

    if ($inTmux) {
        try {
            & tmux set-option -p -u pane-active-border-style 2>$null
            & tmux set-option -p -u pane-border-style 2>$null
        } catch { Write-Verbose "tmux color: $_" }
    } elseif ($env:TERM_PROGRAM -eq 'iTerm.app') {
        Write-Host "${esc}]6;1;bg;*;default${bel}" -NoNewline
    } elseif ($env:WT_SESSION) {
        Write-Host "${esc}]9;9;${esc}\" -NoNewline
    } elseif ($env:KITTY_PID -or $env:TERM_PROGRAM -eq 'kitty') {
        # Kitty: reset by setting to empty
        Write-Host "${esc}]30;${bel}" -NoNewline
    } elseif ($env:KONSOLE_VERSION) {
        Write-Host "${esc}]30;${bel}" -NoNewline
    } elseif ($env:WEZTERM_PANE) {
        # WezTerm: clear user var
        Write-Host "${esc}]1337;SetUserVar=wtw_color=$(
            [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(''))
        )${bel}" -NoNewline
    }
}
