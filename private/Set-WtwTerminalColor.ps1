# Set terminal tab color and title using escape sequences (iTerm2, Windows Terminal, Kitty).
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

    # Set tab/window title
    if ($Title) {
        # OSC 0 — works in iTerm2, Windows Terminal, Kitty, most modern terminals
        Write-Host "${esc}]0;${Title}${bel}" -NoNewline
    }

    # Set tab color from hex
    if ($Color -and $Color -match '^#?([0-9a-fA-F]{6})$') {
        $hex = $Matches[1]
        $r = [convert]::ToInt32($hex.Substring(0, 2), 16)
        $g = [convert]::ToInt32($hex.Substring(2, 2), 16)
        $b = [convert]::ToInt32($hex.Substring(4, 2), 16)

        $termProgram = $env:TERM_PROGRAM

        if ($termProgram -eq 'iTerm.app') {
            # iTerm2 proprietary escape sequence for tab color
            Write-Host "${esc}]6;1;bg;red;brightness;${r}${bel}" -NoNewline
            Write-Host "${esc}]6;1;bg;green;brightness;${g}${bel}" -NoNewline
            Write-Host "${esc}]6;1;bg;blue;brightness;${b}${bel}" -NoNewline
        } elseif ($env:WT_SESSION) {
            # Windows Terminal — set tab color via OSC 9;9
            Write-Host "${esc}]9;9;rgb:$($hex.Substring(0,2))/$($hex.Substring(2,2))/$($hex.Substring(4,2))${esc}\" -NoNewline
        } else {
            # Generic: set cursor/background color hints are not universal,
            # but title is already set above which helps with orientation
        }
    }
}

# Reset terminal tab color to default.
function Reset-WtwTerminalColor {
    [CmdletBinding()]
    param()

    $esc = [char]27
    $bel = [char]7

    $termProgram = $env:TERM_PROGRAM

    if ($termProgram -eq 'iTerm.app') {
        # Reset iTerm2 tab color to default
        Write-Host "${esc}]6;1;bg;*;default${bel}" -NoNewline
    } elseif ($env:WT_SESSION) {
        # Windows Terminal — reset tab color
        Write-Host "${esc}]9;9;${esc}\" -NoNewline
    }
}
