function Connect-WtwRemoteWorktree {
    <#
    .SYNOPSIS
        Open an interactive shell inside a worktree on another machine.
    .DESCRIPTION
        The remote counterpart of `wtw go`: same verb, same intent — be in that
        worktree — except the cd happens over ssh. You land in a normal pwsh
        prompt in the right directory, with your remote profile loaded.

        The terminal title and tab colour are set on the LOCAL machine, because
        that is the window you are looking at. They use the worktree's own colour
        from the remote registry, so a remote session is tinted exactly like the
        local one for that worktree, and both are restored when the session ends.

        Three details make this work where a plain `ssh host` would not:

        * `-t` forces a TTY. Without it ssh runs the command non-interactively and
          pwsh exits immediately.
        * The payload travels as -EncodedCommand, so a path with spaces or quotes
          survives the local shell, ssh's argv concatenation, and cmd.exe on a
          Windows remote.
        * `-NoProfile` is deliberately NOT used here (unlike wtw's scripted
          calls): an interactive session should have the prompt and aliases you
          would get by hand.
    .PARAMETER HostEntry
        Host entry from Resolve-WtwHost.
    .PARAMETER Name
        Target name as the remote wtw knows it. Omit to land in the remote home
        directory — a plain "connect to that machine".
    .PARAMETER PrintOnly
        Print the ssh command instead of running it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [string] $Name,
        [switch] $PrintOnly
    )

    $remotePath = $null
    $label = $HostEntry.Name
    $color = $null

    if ($Name) {
        Write-Host "  Resolving '$Name' on $($HostEntry.Name)..." -ForegroundColor DarkGray
        $remote = Get-WtwRemoteTarget -HostEntry $HostEntry -Name $Name
        if (-not $remote -or -not $remote.Path) {
            # Said locally as well as remotely: the remote may be running an
            # older wtw whose message does not mention it.
            $numericHint = Get-WtwNumericNameHint -Name $Name
            if ($numericHint) { Write-Host "  $numericHint" -ForegroundColor Yellow }
            Show-WtwRemoteTargetSuggestions -HostEntry $HostEntry -Name $Name
            Write-Error "Could not resolve '$Name' on $($HostEntry.Name)."
            return
        }
        $remotePath = $remote.Path
        $color = $remote.Color
        # prettyName carries the worktree's own emoji ("🟢 🏀 PF037 …") — it is
        # what the local tab shows for that worktree, so a remote session reads
        # the same apart from the machine prefix. Title (repo/task) is the
        # fallback for entries that never got a pretty name.
        $label = if ($remote.PrettyName) { $remote.PrettyName }
        elseif ($remote.Title) { $remote.Title }
        else { $Name }
    }

    # Set-Location only; everything else about the session is the user's own
    # remote profile. -NoExit (added by New-WtwRemotePwshCommand) keeps it alive.
    #
    # The existence check is done remotely rather than with a second ssh round
    # trip. A registry entry outliving its directory is normal — someone deletes
    # a worktree without unregistering it — and the failure mode without this is
    # a session that silently starts in the remote home directory with a red
    # Set-Location error scrolled off the top.
    # The title is ALSO set inside the session, not just locally. A Windows
    # remote runs pwsh under ConPTY, which clears the screen and emits its own
    # OSC title ("C:\WINDOWS\system32\conhost.exe") the moment the session
    # starts — clobbering whatever the local terminal was told a moment earlier.
    # Setting it from the far side means the label survives, because that OSC
    # arrives after ConPTY's and travels to the same local terminal.
    $sessionTitle = "$(Get-WtwHostTitlePrefix -HostEntry $HostEntry)$label"
    $titleLiteral = $sessionTitle.Replace("'", "''")
    $setTitle = "try { `$Host.UI.RawUI.WindowTitle = '$titleLiteral' } catch { }"

    $payload = if ($remotePath) {
        $escaped = $remotePath.Replace("'", "''")
        @"
$setTitle
`$wtwTarget = '$escaped'
if (Test-Path -LiteralPath `$wtwTarget) {
    Set-Location -LiteralPath `$wtwTarget
} else {
    Write-Host "  wtw: '`$wtwTarget' is registered but does not exist on this machine." -ForegroundColor Yellow
    Write-Host '  The worktree was probably removed without unregistering it. Fix it here with:' -ForegroundColor DarkGray
    Write-Host '    wtw remove <name>     (drops the stale entry)' -ForegroundColor Cyan
    Write-Host '  Staying in the home directory.' -ForegroundColor DarkGray
}
"@
    } else {
        $setTitle
    }
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($payload))

    $sshArgs = @('-t', $HostEntry.Name) +
    (New-WtwRemotePwshCommand -Encoded $encoded -HostEntry $HostEntry -Interactive)

    if ($PrintOnly) {
        Write-Host "  ssh $($sshArgs -join ' ')" -ForegroundColor White
        return
    }

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        Write-Error 'ssh is not on PATH.'
        return
    }

    $title = $sessionTitle
    Write-Host "  Connecting to $($HostEntry.Name)" -ForegroundColor Green -NoNewline
    if ($remotePath) { Write-Host ": $remotePath" -ForegroundColor Green } else { Write-Host '' }

    Set-WtwTerminalColor -Color $color -Title $title

    try {
        # No BatchMode here: an interactive connect may legitimately need to
        # prompt for a key passphrase.
        & ssh @sshArgs
    } finally {
        # Always restore, including on Ctrl-C — otherwise the local tab keeps the
        # remote worktree's colour long after the session is gone.
        Reset-WtwTerminalColor
        Set-WtwTerminalColor -Title (Get-WtwLocalSessionTitle)
    }
}

function Get-WtwLocalSessionTitle {
    <#
    .SYNOPSIS
        A sensible local title to restore after a remote session.
    .DESCRIPTION
        Prefers the worktree the local shell is actually sitting in, so closing a
        remote session hands the tab back the identity it had. Falls back to the
        current directory's leaf name when the cwd is not a registered worktree.
    #>
    [CmdletBinding()]
    param()

    try {
        $current = Resolve-WtwCurrentTarget
        if ($current) {
            $target = & { Resolve-WtwTarget $current } 6>$null
            if ($target) {
                return $(if ($target.TaskName) { "$($target.RepoName)/$($target.TaskName)" } else { $target.RepoName })
            }
        }
    } catch { Write-Verbose "local title: $_" }

    return (Split-Path -Path (Get-Location).Path -Leaf)
}
