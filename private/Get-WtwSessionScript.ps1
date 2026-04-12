<#
.SYNOPSIS
    Finds a session initialization script file name in a repo root, if present.

.DESCRIPTION
    Looks for start-repository-session.ps1 or start-tools-session.ps1 under RepoPath.

.PARAMETER RepoPath
    Absolute or relative path to the repository root.

.EXAMPLE
    Get-WtwSessionScript -RepoPath 'C:\src\myrepo'

.NOTES
    No external dependencies.
#>
function Get-WtwSessionScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $RepoPath
    )

    $candidates = @(
        'start-repository-session.ps1',
        'start-tools-session.ps1'
    )

    foreach ($name in $candidates) {
        $full = Join-Path $RepoPath $name
        if (Test-Path $full) {
            return $name
        }
    }
    return $null
}
