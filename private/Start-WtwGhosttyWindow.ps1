function Get-WtwGhosttyExe {
    [CmdletBinding()]
    param()

    $cmd = Get-Command ghostty -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    # Ghostty.app does not put its CLI on PATH on macOS.
    $homeDir = if ($HOME) { $HOME } else { $env:USERPROFILE }
    foreach ($appsDir in @('/Applications', $(if ($homeDir) { Join-Path $homeDir 'Applications' }))) {
        if (-not $appsDir) { continue }
        $candidate = Join-Path $appsDir 'Ghostty.app/Contents/MacOS/ghostty'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    return $null
}

function Start-WtwGhosttyWindow {
    <#
    .SYNOPSIS
        Open a new Ghostty window at a directory running a command. Returns
        $false when Ghostty is not installed.
    .DESCRIPTION
        Used to bring up a multiplexer server (herdr, tmux) that wtw then
        drives through its CLI.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkingDirectory,
        [Parameter(Mandatory)][string[]] $Command
    )

    $ghostty = Get-WtwGhosttyExe
    if (-not $ghostty) { return $false }

    # -e must come last: Ghostty passes everything after it to the command.
    Start-Process -FilePath $ghostty -ArgumentList (@("--working-directory=$WorkingDirectory", '-e') + $Command) | Out-Null
    return $true
}
