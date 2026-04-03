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
