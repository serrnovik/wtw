function Open-WtwWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Name,

        [string] $Repo,
        [string] $Editor
    )

    # If no name given, detect from cwd
    if (-not $Name) {
        $Name = Resolve-WtwCurrentTarget
        if (-not $Name) {
            Write-Error "Not inside a registered repo. Specify a target or cd into a repo."
            return
        }
        Write-Host "  Detected: $Name" -ForegroundColor DarkGray
    }

    $config = Get-WtwConfig
    $editorCmd = if ($Editor) { $Editor } elseif ($config.editor) { $config.editor } else { 'code' }

    $target = Resolve-WtwTarget $Name
    if (-not $target) { return }

    if ($target.WorktreeEntry) {
        $wsFile = $target.WorktreeEntry.workspace
    } else {
        $wsFile = $target.RepoEntry.templateWorkspace
    }

    if (-not $wsFile) {
        Write-Error "No workspace found for '$Name'. Run 'wtw list' to see available targets."
        return
    }

    if (-not (Test-Path $wsFile)) {
        Write-Error "Workspace file missing: $wsFile"
        return
    }

    Write-Host "  Opening in ${editorCmd}: $wsFile" -ForegroundColor Green
    & $editorCmd $wsFile
}
