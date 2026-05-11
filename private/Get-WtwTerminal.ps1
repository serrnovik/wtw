function Get-WtwTerminal {
    <#
    .SYNOPSIS
        Identify the host terminal emulator and report what it supports.
    .DESCRIPTION
        Inspects environment variables set by terminal emulators (WT_SESSION,
        WEZTERM_PANE, ConEmuPID, TABBY_CONFIG_DIRECTORY, KITTY_PID, etc.) and
        returns a description of the host terminal, including whether wtw can
        spawn a new tab in it programmatically.
    .OUTPUTS
        PSCustomObject with: Id (short id), Name (human-readable), CanSpawn (bool).
    #>
    [CmdletBinding()]
    param()

    if ($env:WT_SESSION) {
        return [pscustomobject]@{ Id = 'wt';      Name = 'Windows Terminal'; CanSpawn = $true  }
    }
    if ($env:WEZTERM_PANE -or $env:WEZTERM_EXECUTABLE) {
        return [pscustomobject]@{ Id = 'wezterm'; Name = 'WezTerm';           CanSpawn = $true  }
    }
    if ($env:ConEmuPID -or $env:ConEmuDir) {
        return [pscustomobject]@{ Id = 'conemu';  Name = 'ConEmu/Cmder';      CanSpawn = $true  }
    }
    if ($env:TABBY_CONFIG_DIRECTORY -or $env:TERM_PROGRAM -eq 'Tabby') {
        return [pscustomobject]@{ Id = 'tabby';   Name = 'Tabby';             CanSpawn = $false }
    }
    if ($env:KITTY_PID -or $env:TERM_PROGRAM -eq 'kitty') {
        return [pscustomobject]@{ Id = 'kitty';   Name = 'Kitty';             CanSpawn = $false }
    }
    if ($env:KONSOLE_VERSION) {
        return [pscustomobject]@{ Id = 'konsole'; Name = 'Konsole';           CanSpawn = $false }
    }
    if ($env:TERM_PROGRAM -eq 'iTerm.app') {
        return [pscustomobject]@{ Id = 'iterm';   Name = 'iTerm2';            CanSpawn = $false }
    }
    if ($env:TMUX) {
        return [pscustomobject]@{ Id = 'tmux';    Name = 'tmux';              CanSpawn = $false }
    }
    return [pscustomobject]@{ Id = 'other'; Name = 'unknown'; CanSpawn = $false }
}
