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

    # Superset — look up matching workspace by branch/task and open the Superset app
    if ($editorCmd -is [hashtable] -and $editorCmd.type -eq 'superset') {
        Open-WtwSupersetWorkspace -Target $target
        return
    }

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
            if ($editorCmd.macArgsViaCli) {
                # `open -a` routes paths as Apple "open file" events; many Avalonia apps don't handle them,
                # and `open -n --args` silently drops --args when LSMultipleInstancesProhibited is set.
                # Invoke the inner Mach-O directly so argv reaches main() — for IPC-aware apps (e.g.
                # SourceGit), the spawned second instance forwards the path to the running first instance
                # via its named-pipe IPC and exits.
                $bin = "/Applications/$found.app/Contents/MacOS/$found"
                if (Test-Path $bin) {
                    Start-Process -FilePath $bin -ArgumentList $dir
                } else {
                    Write-Warning "Binary not found at $bin — falling back to 'open -a'."
                    & open -a $found $dir
                }
            } else {
                & open -a $found $dir
            }
        } elseif ($IsWindows -and $editorCmd.winCmd) {
            $exe = (Get-Command $editorCmd.winCmd -ErrorAction SilentlyContinue)?.Source
            if (-not $exe) {
                $probe = @(
                    (Join-Path ${env:LOCALAPPDATA} "$($editorCmd.winCmd)/$($editorCmd.winCmd).exe"),
                    (Join-Path ${env:ProgramFiles}   "$($editorCmd.winCmd)/$($editorCmd.winCmd).exe")
                ) | Where-Object { $_ -and (Test-Path $_) }
                $exe = $probe | Select-Object -First 1
            }
            if (-not $exe) { Write-Error "$appName not found on PATH or in standard locations."; return }
            Write-Host "  Opening in ${appName}: $dir" -ForegroundColor Green
            Start-Process -FilePath $exe -ArgumentList $dir
        } elseif ($IsLinux -and $editorCmd.linuxCmd) {
            $exe = (Get-Command $editorCmd.linuxCmd -ErrorAction SilentlyContinue)?.Source
            if (-not $exe) { Write-Error "'$appName' not installed (no '$($editorCmd.linuxCmd)' on PATH)."; return }
            Write-Host "  Opening in ${appName}: $dir" -ForegroundColor Green
            Start-Process -FilePath $exe -ArgumentList $dir
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
