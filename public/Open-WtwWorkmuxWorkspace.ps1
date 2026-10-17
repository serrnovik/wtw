function Open-WtwWorkmuxWorkspace {
    <#
    .SYNOPSIS
        Open a wtw target as a workmux tmux window.
    .DESCRIPTION
        Runs `workmux open <dir-name>` from the target directory: workmux reads
        `git worktree list`, so it already knows wtw's worktrees and the main
        checkout. It switches to the existing `wm-<dir>` window or creates one.
        When no tmux server is running, a tmux session is started in a new
        Ghostty window first.
    .PARAMETER Target
        Resolved wtw target object (output of Resolve-WtwTarget).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Target
    )

    if (-not (Get-WtwWorkmuxExe)) {
        Write-Error @'
Could not find workmux. Install it with `cargo install workmux` (see
https://workmux.raine.dev), or set $env:WTW_WORKMUX to the workmux binary.
'@
        return
    }

    $metadata = Resolve-WtwTerminalWorkspaceMetadata -Target $Target
    if (-not ($metadata -and $metadata.Path -and (Test-Path $metadata.Path))) {
        Write-Error 'No directory found for workmux target.'
        return
    }

    $result = Open-WtwWorkmuxProject -ProjectPath $metadata.Path
    if (-not $result.Success) {
        Write-WtwHost "  workmux: $($result.Reason)" -ForegroundColor Yellow
        Write-WtwHost "  Target would be: '$($metadata.PrettyName)' -> $($metadata.Path)" -ForegroundColor DarkGray
        $global:LASTEXITCODE = 1
        return
    }

    $verb = if ($result.Started) { 'started tmux in Ghostty and opened window' } elseif ($result.Created) { 'opened window' } else { 'switched to window' }
    Write-WtwHost "  workmux: $verb 'wm-$($result.Name)' for '$($metadata.PrettyName)'" -ForegroundColor Green
    Write-WtwHost "  Path: $($metadata.Path)" -ForegroundColor DarkGray
    if (-not $env:TMUX -and -not $result.Started) {
        Write-WtwHost '  Not inside tmux: attach with `tmux attach`.' -ForegroundColor DarkGray
    }
    $global:LASTEXITCODE = 0
}
