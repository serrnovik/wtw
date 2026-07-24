function Enter-WtwWorktree {
    <#
    .SYNOPSIS
        Switch to a worktree directory and run session initialization.
    .DESCRIPTION
        Resolves the target by repo alias, task name, or alias-task combo,
        changes to its directory, and runs the repo session script if available.
    .PARAMETER Name
        Repo alias, task name, or alias-task combo (e.g. "app-auth").
    .EXAMPLE
        wtw go auth
        Switch to the "auth" worktree directory and initialize the session.
    .NOTES
        Side effects:
        - Changes the current location (Set-Location) to the worktree directory.
        - Sets WTW_* and DEV_WORKTREE_* environment variables for tooling integration.
        - May run a repo session script (e.g. start-repository-session.ps1) if configured.
        - Sets terminal tab color and title via escape sequences when no session script handles it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,

        [switch] $NewTab
    )

    $target = Resolve-WtwTarget $Name
    if (-not $target) { return }

    $repo = $target.RepoEntry
    $sessionScript = $repo.sessionScript

    if ($target.WorktreeEntry) {
        $targetPath = $target.WorktreeEntry.path
    } else {
        $targetPath = $repo.mainPath
    }

    if (-not (Test-Path $targetPath)) {
        $resolvedLabel = if ($target.TaskName) { "$($target.RepoName) / $($target.TaskName)" } else { $target.RepoName }
        Write-Host ''
        Write-Host '  ✗  Worktree path not found' -ForegroundColor Red
        Write-Host ''
        Write-Host "  Resolved:  $resolvedLabel" -ForegroundColor DarkGray
        Write-Host "  Path:      $targetPath" -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  The worktree is registered but its directory no longer exists.' -ForegroundColor Yellow
        Write-Host "  To recreate:    wtw create $Name" -ForegroundColor Cyan
        Write-Host "  To unregister:  wtw remove $Name" -ForegroundColor Cyan
        Write-Host ''
        return
    }

    # Resolve the color for this target (for terminal tab coloring)
    $targetColor = if ($target.WorktreeEntry) {
        $target.WorktreeEntry.color
    } else {
        Get-WtwPropertyValue -Object (Get-WtwColors).assignments -Name "$($target.RepoName)/main"
    }
    $targetTitle = if ($target.TaskName) {
        "$($target.RepoName)/$($target.TaskName)"
    } else {
        $target.RepoName
    }
    $prNumber = Get-WtwCurrentPrNumber
    $titleWithPr = if ($prNumber) { "$targetTitle #$prNumber" } else { $targetTitle }

    # --new-tab: spawn a fresh tab in whatever terminal we're currently in.
    # Detection is by env var (WT_SESSION, WEZTERM_PANE, ConEmuPID, ...), so we
    # don't accidentally pop a Windows Terminal window when the user is running
    # pwsh inside WezTerm or ConEmu.
    if ($NewTab) {
        $term = Get-WtwTerminal
        $aliases = Get-WtwRepoAliases $repo
        $primaryAlias = if ($aliases -and $aliases.Count -gt 0) { $aliases[0] } else { $target.RepoName }
        $nameArg = if ($target.TaskName) { "$primaryAlias-$($target.TaskName)" } else { $primaryAlias }
        $innerCmd = "wtw go $nameArg"

        $spawned = $false
        switch ($term.Id) {
            'wt' {
                if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
                    & wt.exe -w 0 new-tab `
                        --tabColor $targetColor `
                        --title    $titleWithPr `
                        -d         $targetPath `
                        pwsh -NoLogo -NoExit -Command $innerCmd
                    $spawned = $true
                }
            }
            'wezterm' {
                # WezTerm sets initial title via the inner pwsh's OSC 0. Tab
                # background colour requires user Lua config — out of scope here.
                if (Get-Command wezterm -ErrorAction SilentlyContinue) {
                    & wezterm cli spawn --cwd $targetPath -- pwsh -NoLogo -NoExit -Command $innerCmd
                    Write-Host '  Note: WezTerm tab background colour requires user Lua config.' -ForegroundColor DarkGray
                    $spawned = $true
                }
            }
            'conemu' {
                # ConEmu: -reuse opens a new tab in the existing window. There is
                # no portable escape for runtime tab color in ConEmu.
                $conemuExe = Get-Command ConEmu64.exe -ErrorAction SilentlyContinue
                if (-not $conemuExe) { $conemuExe = Get-Command ConEmu.exe -ErrorAction SilentlyContinue }
                if ($conemuExe) {
                    & $conemuExe.Path -reuse -dir $targetPath -cmd pwsh -NoLogo -NoExit -Command $innerCmd
                    Write-Host '  Note: ConEmu tab colour must be configured per-Task in ConEmu settings.' -ForegroundColor DarkGray
                    $spawned = $true
                }
            }
        }

        if ($spawned) { return }

        if (-not $term.CanSpawn) {
            Write-Host "  --new-tab not automatable in this terminal ($($term.Name))." -ForegroundColor Yellow
        } else {
            Write-Host "  Could not locate the spawn CLI for $($term.Name)." -ForegroundColor Yellow
        }
        Write-Host "  Open a new tab manually, then run:  wtw go $nameArg" -ForegroundColor DarkGray
        Write-Host '  Falling back to in-place switch.' -ForegroundColor DarkGray
    }

    # Set worktree environment variables (WTW_*, DEV_WORKTREE_*)
    Set-WtwWorktreeEnv -TaskName $target.TaskName -RepoEntry $repo

    # Always set tab title (and color where supported) BEFORE running the session
    # script. The script's own prompt hook may overwrite the title afterwards —
    # that's expected and fine; this guarantees something sensible if it doesn't.
    Set-WtwTerminalColor -Color $targetColor -Title $titleWithPr

    try {
        # Use Set-GitRepo if available (from user profile), otherwise direct approach
        if (Get-Command 'Set-GitRepo' -ErrorAction SilentlyContinue) {
            $toolName = if ($sessionScript) { $sessionScript } else { 'start-repository-session.ps1' }
            Set-GitRepo -gitRoot $targetPath -toolName $toolName
        } else {
            Set-Location $targetPath
            if ($sessionScript) {
                $scriptPath = Join-Path $targetPath $sessionScript
                if (Test-Path $scriptPath) { & $scriptPath }
            }
            Write-Host "  Switched to: $targetPath" -ForegroundColor Green
        }

        # Inside a cmux surface, also push the workspace/tab metadata (icon'd tab label,
        # color, status). Set-WtwTerminalColor above only sets the OSC window title, which
        # cmux ignores for the tab label — the tab is controlled by `cmux rename-tab`.
        # MUST run BEFORE the finally's Restore-WtwInstalledModule (-Force re-import), which
        # would otherwise invalidate by-name resolution of the private cmux functions.
        # Skip when called BY Initialize-WtwCmuxCurrentSession -ApplyTerminalSession (it
        # applies the metadata itself) so we don't double-apply.
        if ($env:CMUX_WORKSPACE_ID -and -not $script:WtwCmuxApplyingFromInit) {
            try { Initialize-WtwCmuxCurrentSession } catch {}
        }
    } finally {
        Restore-WtwInstalledModule
    }
}
