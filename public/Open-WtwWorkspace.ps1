function Open-WtwWorkspace {
    <#
    .SYNOPSIS
        Open a workspace file in the configured editor.
    .DESCRIPTION
        Opens the VS Code workspace file for the given target. Falls back to
        opening the directory if no workspace file exists. Auto-detects the
        target from cwd when no name is provided.
    .PARAMETER Name
        Target repo alias or task name (default: detected from cwd).
    .PARAMETER Repo
        Specify the parent repo when the name alone is ambiguous.
    .PARAMETER Editor
        Override the editor command (defaults to config or "code").
    .EXAMPLE
        wtw open auth
        Open the workspace for the "auth" worktree in the default editor.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Name,

        [string] $Repo,
        [object] $Editor  # string for CLI editors; hashtable @{type='macapp'; appName=...} for open-app style
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

    # macOS/cross-platform open-app style (Codex, Claude, T3 Code, etc.) — always opens directory
    if ($editorCmd -is [hashtable] -and $editorCmd.type -eq 'macapp') {
        $appName = $editorCmd.appName
        $dir = if ($target.WorktreeEntry) { $target.WorktreeEntry.path } else { $target.RepoEntry.mainPath }
        if (-not ($dir -and (Test-Path $dir))) {
            Write-Error "No directory found for '$Name'."
            return
        }

        if ($IsMacOS) {
            $candidates = $editorCmd.appNameCandidates ?? @($appName)
            $found = $candidates | Where-Object { Test-Path "/Applications/$_.app" } | Select-Object -First 1
            if (-not $found) {
                $tried = ($candidates | ForEach-Object { "$_.app" }) -join ', '
                Write-Error "$appName is not installed. Tried: $tried"
                return
            }
            Write-Host "  Opening in ${found}: $dir" -ForegroundColor Green
            & open -a $found $dir
        } elseif ($IsWindows -and $editorCmd.winCmd) {
            Write-Host "  Opening in $($editorCmd.winCmd): $dir" -ForegroundColor Green
            & $editorCmd.winCmd $dir
        } else {
            $platform = if ($IsWindows) { 'Windows' } elseif ($IsLinux) { 'Linux' } else { 'this platform' }
            Write-Warning "'$appName' app launch is not supported on $platform."
        }
        return
    }

    if ($target.WorktreeEntry) {
        $wsFile = $target.WorktreeEntry.workspace
    } else {
        $wsFile = $target.RepoEntry.templateWorkspace
    }

    # Workspace file found — open it
    if ($wsFile -and (Test-Path $wsFile)) {
        Write-Host "  Opening in ${editorCmd}: $wsFile" -ForegroundColor Green
        & $editorCmd $wsFile
        return
    }

    # No workspace file — fall back to opening the directory
    $dir = if ($target.WorktreeEntry) { $target.WorktreeEntry.path } else { $target.RepoEntry.mainPath }
    if ($dir -and (Test-Path $dir)) {
        Write-Host "  Opening in ${editorCmd}: $dir" -ForegroundColor Green
        & $editorCmd $dir
    } else {
        Write-Error "No workspace or directory found for '$Name'."
    }
}
