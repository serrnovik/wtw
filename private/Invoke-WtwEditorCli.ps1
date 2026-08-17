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
        candidate chains come from the shared family table
        (private/Get-WtwEditorFamily.ps1), so install-time detection and
        launch-time invocation can't drift apart again.
    .PARAMETER Cmd
        Logical editor command (e.g. 'antigravity', 'cursor', 'code').
    .PARAMETER Path
        File or directory to open. Omitted for remote launches, where the
        target travels in -PreArgs as a `--folder-uri` / `--file-uri` value.
    .PARAMETER PreArgs
        Extra arguments inserted before Path. Used by the remote opener to pass
        `--remote ssh-remote+<host>` / `--folder-uri vscode-remote://…`.
    .PARAMETER PassThru
        Return the resolved invocation as @{ Exe; Arguments } instead of running
        it. Lets `--print-only` and the tests inspect the exact command line.
    #>
    param(
        [Parameter(Mandatory)] [string] $Cmd,
        [string] $Path,
        [string[]] $PreArgs = @(),
        [switch] $PassThru
    )

    $member     = Get-WtwEditorFamilyMember -Id $Cmd
    $candidates = if ($member) { @($member.Cli) } else { @($Cmd) }
    $macApps    = if ($member) { @($member.MacApps) } else { @() }
    $flags      = if ($member) { @($member.LaunchFlags) } else { @() }

    $arguments = @($flags) + @($PreArgs)
    if ($Path) { $arguments += $Path }

    # 1. First CLI candidate that resolves to a real, runnable binary.
    $runnable = $candidates | Where-Object { Test-WtwEditorCli -Cmd $_ } | Select-Object -First 1
    if ($runnable) {
        if ($PassThru) { return @{ Exe = $runnable; Arguments = $arguments } }
        & $runnable @arguments
        return
    }

    # 2. macOS: CLI missing/broken but the app bundle is installed — open it.
    #    `open -a` can only carry a filesystem path, so a remote launch (which
    #    needs --folder-uri) has no bundle fallback and must report the missing CLI.
    if ($IsMacOS -and $macApps.Count -gt 0 -and $PreArgs.Count -eq 0 -and $Path) {
        $app = $macApps | Where-Object { Test-Path "/Applications/$_.app" } | Select-Object -First 1
        if ($app) {
            if ($PassThru) { return @{ Exe = 'open'; Arguments = @('-a', $app, $Path) } }
            Write-Host "  '$Cmd' CLI not on PATH — opening /Applications/$app.app instead." -ForegroundColor DarkGray
            Write-Host "  Tip: in $app, run Cmd-Shift-P → 'Shell Command: Install ... command in PATH' to enable the CLI." -ForegroundColor DarkGray
            & open -a $app $Path
            return
        }
    }

    # 3. Nothing usable found.
    $tried = $candidates -join ', '
    if ($PreArgs.Count -gt 0) {
        Write-Error "Editor '$Cmd' is not runnable (tried CLI: $tried). A remote open needs the editor CLI on PATH — the .app bundle fallback cannot pass a remote URI."
        return
    }
    Write-Error "Editor '$Cmd' is not runnable (tried CLI: $tried). Install it or set a different 'editor' in your wtw config."
}

function Get-WtwEditorCliName {
    <#
    .SYNOPSIS
        The runnable CLI name for a logical editor, or $null.
    .DESCRIPTION
        Same candidate chain Invoke-WtwEditorCli launches through, exposed for
        callers that need to run the CLI for something other than opening a
        path — `--list-extensions`, `--install-extension`.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Cmd)

    $member = Get-WtwEditorFamilyMember -Id $Cmd
    $candidates = if ($member) { @($member.Cli) } else { @($Cmd) }
    return ($candidates | Where-Object { Test-WtwEditorCli -Cmd $_ } | Select-Object -First 1)
}
