function Open-WtwWmuxWorkspace {
    <#
    .SYNOPSIS
        Open a wtw target as a wmux workspace.
    .DESCRIPTION
        Creates a named wmux workspace rooted at the target directory using the
        supported wmux CLI shape: `wmux new-workspace --title <name> --cwd <path>`.
        Existing tabs are matched by cwd first, then renamed to the composed
        title (repo emoji + worktree emoji + form name) and selected so the
        workspace is visible. wmux is Windows-only; cmux remains the macOS equivalent.
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
        $global:LASTEXITCODE = 1
        return
    }

    if (-not (Test-WtwWmuxPresent)) {
        Write-Error @'
Could not find the wmux CLI. wmux ships without an installer, so wtw locates it
via (in order): $env:WMUX_EXE, a running wmux process, `wmux.exe` on PATH, then
common install dirs. Install wmux from https://github.com/amirlehmam/wmux, or set
$env:WMUX_EXE to its wmux.exe. The CLI is `resources/cli/wmux.js` run with Node, or
with wmux.exe itself via ELECTRON_RUN_AS_NODE when `node` is not on PATH.
'@
        $global:LASTEXITCODE = 1
        return
    }

    $metadata = Resolve-WtwTerminalWorkspaceMetadata -Target $Target
    if (-not ($metadata -and $metadata.Path -and (Test-Path $metadata.Path))) {
        Write-Error 'No directory found for wmux target.'
        $global:LASTEXITCODE = 1
        return
    }

    $result = Open-WtwWmuxProject -ProjectPath $metadata.Path -PrettyName $metadata.PrettyName -StatusValue $metadata.StatusValue
    if (-not $result.Success) {
        Write-Host "  wmux: $($result.Reason)" -ForegroundColor Yellow
        Write-Host "  Target would be: '$($metadata.PrettyName)' -> $($metadata.Path)" -ForegroundColor DarkGray
        $global:LASTEXITCODE = 1
        return
    }

    Save-WtwWmuxWorkspaceName -Target $Target -WorkspaceName $metadata.PrettyName

    $colorSuffix = if ($metadata.Color) { " [$($metadata.Color)]" } else { '' }
    $verb = if ($result.Created) { 'created' } else { 'opened' }
    Write-Host "  wmux: $verb workspace '$($metadata.PrettyName)'$colorSuffix" -ForegroundColor Green
    Write-Host "  Path: $($metadata.Path)" -ForegroundColor DarkGray
    # Ping / CLI leftovers otherwise leak into Starship as ERROR 1 after a successful open.
    $global:LASTEXITCODE = 0
}
