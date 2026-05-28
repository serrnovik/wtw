function Get-WtwGitCommand {
    <#
    .SYNOPSIS
        Resolve a runnable git executable for optional WTW metadata lookups.
    .DESCRIPTION
        Some agent or app-launched PowerShell sessions have a reduced PATH.
        WTW should still list registered worktrees in those sessions, so this
        helper checks PATH first and then common install locations.
    #>
    [CmdletBinding()]
    param()

    $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gitCommand) {
        return $gitCommand.Source
    }

    $candidates = @(
        '/opt/homebrew/bin/git',
        '/usr/local/bin/git',
        '/usr/bin/git',
        "$env:ProgramFiles\Git\cmd\git.exe",
        "${env:ProgramFiles(x86)}\Git\cmd\git.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return $null
}
