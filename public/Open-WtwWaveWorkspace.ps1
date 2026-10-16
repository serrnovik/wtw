function Open-WtwWaveWorkspace {
    <#
    .SYNOPSIS
        Open a wtw target as a Wave Terminal block.
    .DESCRIPTION
        Focuses the terminal block in the current Wave tab that is already
        rooted at the target directory, or opens a new one with
        `wsh term <path>`. The block is titled with the wtw pretty name and its
        frame is tinted with the worktree color. Must run from a Wave terminal,
        because wsh only reaches the app through the token Wave injects there.
    .PARAMETER Target
        Resolved wtw target object (output of Resolve-WtwTarget).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Target
    )

    if (-not (Get-WtwWshExe)) {
        Write-Error @'
Could not find wsh, the Wave Terminal CLI. Wave puts it on PATH inside its own
terminals (and in $env:WAVETERM_WSHBINDIR). Install Wave from https://waveterm.dev,
or set $env:WTW_WSH to the wsh binary.
'@
        return
    }

    $metadata = Resolve-WtwTerminalWorkspaceMetadata -Target $Target
    if (-not ($metadata -and $metadata.Path -and (Test-Path $metadata.Path))) {
        Write-Error 'No directory found for Wave target.'
        return
    }

    $result = Open-WtwWaveProject -ProjectPath $metadata.Path -PrettyName $metadata.PrettyName -Color $metadata.Color
    if (-not $result.Success) {
        Write-WtwHost "  wave: $($result.Reason)" -ForegroundColor Yellow
        Write-WtwHost "  Target would be: '$($metadata.PrettyName)' -> $($metadata.Path)" -ForegroundColor DarkGray
        $global:LASTEXITCODE = 1
        return
    }

    $colorSuffix = if ($metadata.Color) { " [$($metadata.Color)]" } else { '' }
    $verb = if ($result.Created) { 'opened new block' } else { 'focused block' }
    Write-WtwHost "  wave: $verb '$($metadata.PrettyName)'$colorSuffix" -ForegroundColor Green
    Write-WtwHost "  Path: $($metadata.Path)" -ForegroundColor DarkGray
    $global:LASTEXITCODE = 0
}
