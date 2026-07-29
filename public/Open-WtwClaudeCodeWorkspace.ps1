function Open-WtwClaudeCodeWorkspace {
    <#
    .SYNOPSIS
        Open a wtw target as a new Claude Code chat in the Claude desktop app.
    .DESCRIPTION
        Uses the app's `claude://code/new?folder=<dir>` deep link so the chat is
        rooted at the worktree instead of whatever directory the app last used.

        Unlike Cursor and ChatGPT, the Claude desktop app owns its own session
        titles (auto-generated from the first message, renameable in the UI) and
        exposes no hook for setting one at launch — the worktree folder is what
        identifies the session. `-Prompt` pre-fills the composer, which is the
        closest wtw can get to seeding a label.
    .PARAMETER Target
        Resolved wtw target object (output of Resolve-WtwTarget).
    .PARAMETER Editor
        Resolved editor metadata; supplies appNameCandidates when present.
    .PARAMETER Prompt
        Optional text to pre-fill the new chat's composer with (not submitted).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Target,

        [object] $Editor,

        [string] $Prompt
    )

    $dir = if ($Target.WorktreeEntry) { $Target.WorktreeEntry.path } else { $Target.RepoEntry.mainPath }
    if (-not ($dir -and (Test-Path $dir))) {
        Write-Error 'No directory found for Claude Code target.'
        return
    }

    $candidates = Get-WtwPropertyValue -Object $Editor -Name 'appNameCandidates' -DefaultValue @('Claude')
    $result = Start-WtwClaudeCodeSession -ProjectPath $dir -Prompt $Prompt -AppNameCandidates $candidates

    if (-not $result.Success) {
        Write-Error $result.Reason
        return
    }

    $label = Get-WtwPropertyValue -Object $Target.WorktreeEntry -Name 'prettyName'
    if (-not $label) { $label = $Target.TaskName }
    if (-not $label) { $label = Split-Path $dir -Leaf }

    Write-Host "  Claude Code: new chat in '$label'" -ForegroundColor Green
    Write-Host "  Path: $([System.IO.Path]::GetFullPath($dir))" -ForegroundColor DarkGray
}
