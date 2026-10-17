function Open-WtwHerdrWorkspace {
    <#
    .SYNOPSIS
        Open a wtw target as a herdr workspace.
    .DESCRIPTION
        Focuses the herdr workspace that already has a pane rooted at the
        target directory (relabelling it with the wtw pretty name), or creates
        one with `herdr workspace create --cwd <path> --label <name>`. When no
        herdr server is running, herdr is started in a new Ghostty window at the
        target. Herdr has no workspace color; the color emoji in the pretty name
        carries it.
    .PARAMETER Target
        Resolved wtw target object (output of Resolve-WtwTarget).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Target
    )

    if (-not (Get-WtwHerdrExe)) {
        Write-Error @'
Could not find herdr. Install it from https://herdr.dev (release binary into
~/.local/bin), or set $env:WTW_HERDR to the herdr binary.
'@
        return
    }

    $metadata = Resolve-WtwTerminalWorkspaceMetadata -Target $Target
    if (-not ($metadata -and $metadata.Path -and (Test-Path $metadata.Path))) {
        Write-Error 'No directory found for herdr target.'
        return
    }

    $result = Open-WtwHerdrProject -ProjectPath $metadata.Path -PrettyName $metadata.PrettyName
    if (-not $result.Success) {
        Write-WtwHost "  herdr: $($result.Reason)" -ForegroundColor Yellow
        Write-WtwHost "  Target would be: '$($metadata.PrettyName)' -> $($metadata.Path)" -ForegroundColor DarkGray
        $global:LASTEXITCODE = 1
        return
    }

    $verb = if ($result.Started) { 'started in Ghostty with workspace' } elseif ($result.Created) { 'created workspace' } else { 'focused workspace' }
    Write-WtwHost "  herdr: $verb '$($metadata.PrettyName)' [$($result.Id)]" -ForegroundColor Green
    Write-WtwHost "  Path: $($metadata.Path)" -ForegroundColor DarkGray
    $global:LASTEXITCODE = 0
}
