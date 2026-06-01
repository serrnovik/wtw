function Open-WtwWmuxWorkspace {
    <#
    .SYNOPSIS
        Open a wtw target as a wmux workspace.
    .DESCRIPTION
        Creates a named wmux workspace rooted at the target directory using the
        supported wmux CLI shape: `wmux new-workspace --title <name> --cwd <path>`.
        wmux is Windows-only; cmux remains the macOS equivalent.
    .PARAMETER Target
        Resolved wtw target object (output of Resolve-WtwTarget).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Target
    )

    if (-not $IsWindows) {
        Write-Error 'wmux is Windows-only. On macOS, use `wtw cmux <name>`.'
        return
    }

    if (-not (Test-WtwWmuxPresent)) {
        Write-Error "wmux is not installed or not on PATH. Install it with 'winget install openwong2kim.wmux'."
        return
    }

    $metadata = Resolve-WtwTerminalWorkspaceMetadata -Target $Target
    if (-not ($metadata -and $metadata.Path -and (Test-Path $metadata.Path))) {
        Write-Error 'No directory found for wmux target.'
        return
    }

    $result = Open-WtwWmuxProject -ProjectPath $metadata.Path -PrettyName $metadata.PrettyName -StatusValue $metadata.StatusValue
    if (-not $result.Success) {
        Write-Host "  wmux: $($result.Reason)" -ForegroundColor Yellow
        Write-Host "  Target would be: '$($metadata.PrettyName)' -> $($metadata.Path)" -ForegroundColor DarkGray
        return
    }

    $colorSuffix = if ($metadata.Color) { " [$($metadata.Color)]" } else { '' }
    Write-Host "  wmux: opened workspace '$($metadata.PrettyName)'$colorSuffix" -ForegroundColor Green
    Write-Host "  Path: $($metadata.Path)" -ForegroundColor DarkGray
}
