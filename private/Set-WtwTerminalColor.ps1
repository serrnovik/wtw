# Set terminal tab color and title using escape sequences.
# Supported: iTerm2, Windows Terminal, Kitty, Konsole, WezTerm, tmux.
# Unsupported terminals (Terminal.app, GNOME Terminal, Alacritty, etc.) get title only.
function Set-WtwTerminalColor {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Color,

        [Parameter(Position = 1)]
        [string] $Title
    )

    $esc = [char]27
    $bel = [char]7
    $inTmux = $null -ne $env:TMUX

    # Set tab/window title — OSC 0 works nearly everywhere
    if ($Title) {
        if ($inTmux) {
            # tmux: passthrough + set pane title
            Write-Host "${esc}]0;${Title}${bel}" -NoNewline
            Write-Host "${esc}k${Title}${esc}\" -NoNewline
        } else {
            Write-Host "${esc}]0;${Title}${bel}" -NoNewline
        }
    }

    # Set tab color from hex
    if ($Color -and $Color -match '^#?([0-9a-fA-F]{6})$') {
        $hex = $Matches[1]
        $r = [convert]::ToInt32($hex.Substring(0, 2), 16)
        $g = [convert]::ToInt32($hex.Substring(2, 2), 16)
        $b = [convert]::ToInt32($hex.Substring(4, 2), 16)

        $termProgram = $env:TERM_PROGRAM

        if ($inTmux) {
            # tmux: set pane border and status bar color via tmux commands
            $hexColor = "#${hex}"
            try {
                & tmux select-pane -P "bg=default" 2>$null
                & tmux set-option -p pane-active-border-style "fg=${hexColor}" 2>$null
                & tmux set-option -p pane-border-style "fg=${hexColor}" 2>$null
            } catch {}
        } elseif ($termProgram -eq 'iTerm.app') {
            # iTerm2 proprietary escape for tab color
            Write-Host "${esc}]6;1;bg;red;brightness;${r}${bel}" -NoNewline
            Write-Host "${esc}]6;1;bg;green;brightness;${g}${bel}" -NoNewline
            Write-Host "${esc}]6;1;bg;blue;brightness;${b}${bel}" -NoNewline
        } elseif ($env:WT_SESSION) {
            # Windows Terminal — OSC 9;9
            Write-Host "${esc}]9;9;rgb:$($hex.Substring(0,2))/$($hex.Substring(2,2))/$($hex.Substring(4,2))${esc}\" -NoNewline
        } elseif ($env:KITTY_PID -or $termProgram -eq 'kitty') {
            # Kitty — OSC 30 sets the tab/window title bar color
            Write-Host "${esc}]30;#${hex}${bel}" -NoNewline
        } elseif ($env:KONSOLE_VERSION) {
            # Konsole — same OSC 30 as Kitty
            Write-Host "${esc}]30;#${hex}${bel}" -NoNewline
        } elseif ($env:WEZTERM_PANE) {
            # WezTerm — set tab color via user var
            Write-Host "${esc}]1337;SetUserVar=wtw_color=$(
                [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("#${hex}"))
            )${bel}" -NoNewline
        }
        # Unsupported terminals (Terminal.app, GNOME Terminal, Alacritty, foot, etc.)
        # fall through — title is already set above for orientation
    }
}

# Reset terminal tab color to default.
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
        } catch {}
    } elseif ($env:TERM_PROGRAM -eq 'iTerm.app') {
        Write-Host "${esc}]6;1;bg;*;default${bel}" -NoNewline
    } elseif ($env:WT_SESSION) {
        Write-Host "${esc}]9;9;${esc}\" -NoNewline
    } elseif ($env:KITTY_PID -or $env:TERM_PROGRAM -eq 'kitty') {
        # Kitty: reset by setting to empty
        Write-Host "${esc}]30;${bel}" -NoNewline
    } elseif ($env:KONSOLE_VERSION) {
        Write-Host "${esc}]30;${bel}" -NoNewline
    }
}
