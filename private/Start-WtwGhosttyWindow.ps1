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

    $ghostty = Get-Command ghostty -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ghostty) { return $false }

    # -e must come last: Ghostty passes everything after it to the command.
    Start-Process -FilePath $ghostty.Source -ArgumentList (@("--working-directory=$WorkingDirectory", '-e') + $Command) | Out-Null
    return $true
}
