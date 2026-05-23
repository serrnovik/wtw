function Invoke-WtwEditorCli {
    <#
    .SYNOPSIS
        Launch a CLI-style editor on a path, surviving editor CLI renames.
    .DESCRIPTION
        `wtw open` etc. used to do `& $editor $path` against the bare name
        from config / the resolver. That breaks when an editor renames its
        CLI between major versions and leaves a dangling stub on PATH — e.g.
        Antigravity v2 ships its CLI as `antigravity-ide` (app: "Antigravity
        IDE.app") while the v1 installer's `~/.antigravity/.../bin/antigravity`
        stub lingers and points at a binary that no longer exists.

        This helper resolves the logical editor name to the first CLI
        candidate that actually runs (via Test-WtwEditorCli), and on macOS
        falls back to launching the installed .app bundle by name. The
        candidate chains live here so install-time detection and launch-time
        invocation can't drift apart again.
    .PARAMETER Cmd
        Logical editor command (e.g. 'antigravity', 'cursor', 'code').
    .PARAMETER Path
        File or directory to open.
    #>
    param(
        [Parameter(Mandatory)] [string] $Cmd,
        [Parameter(Mandatory)] [string] $Path
    )

    # Known CLI renames: logical name -> ordered CLI candidates (newest first).
    # macApps -> ordered macOS .app bundle names for the open-bundle fallback.
    $launch = @{
        'antigravity' = @{ candidates = @('antigravity-ide', 'antigravity'); macApps = @('Antigravity IDE', 'Antigravity') }
        'cursor'      = @{ candidates = @('cursor');      macApps = @('Cursor') }
        'code'        = @{ candidates = @('code');        macApps = @('Visual Studio Code') }
        'windsurf'    = @{ candidates = @('windsurf');    macApps = @('Windsurf') }
        'codium'      = @{ candidates = @('codium');      macApps = @('VSCodium') }
    }

    $spec       = $launch[$Cmd]
    $candidates = if ($spec) { $spec.candidates } else { @($Cmd) }
    $macApps    = if ($spec) { $spec.macApps }    else { @() }

    # 1. First CLI candidate that resolves to a real, runnable binary.
    $runnable = $candidates | Where-Object { Test-WtwEditorCli -Cmd $_ } | Select-Object -First 1
    if ($runnable) {
        & $runnable $Path
        return
    }

    # 2. macOS: CLI missing/broken but the app bundle is installed — open it.
    if ($IsMacOS -and $macApps.Count -gt 0) {
        $app = $macApps | Where-Object { Test-Path "/Applications/$_.app" } | Select-Object -First 1
        if ($app) {
            Write-Host "  '$Cmd' CLI not on PATH — opening /Applications/$app.app instead." -ForegroundColor DarkGray
            Write-Host "  Tip: in $app, run Cmd-Shift-P → 'Shell Command: Install ... command in PATH' to enable the CLI." -ForegroundColor DarkGray
            & open -a $app $Path
            return
        }
    }

    # 3. Nothing usable found.
    $tried = $candidates -join ', '
    Write-Error "Editor '$Cmd' is not runnable (tried CLI: $tried). Install it or set a different 'editor' in your wtw config."
}
