function Test-WtwIsSshTransportError {
    <#
    .SYNOPSIS
        Did ssh itself fail, or did the remote command run and report an error?
    .DESCRIPTION
        Both arrive on stderr, and conflating them is actively misleading: a
        remote `wtw` saying "could not resolve X" was printed by a session that
        connected perfectly, so labelling it "ssh to host failed" sends you off
        debugging the network instead of the name you typed.

        Only the transport failures Format-WtwSshError knows how to advise on
        count as ssh problems; anything else is the remote command talking.
    #>
    [CmdletBinding()]
    param([AllowNull()] [string] $ErrorText)

    if (-not $ErrorText) { return $false }
    return ($ErrorText -match 'Host key verification failed' -or
        $ErrorText -match 'Permission denied' -or
        $ErrorText -match 'Could not resolve hostname|Name or service not known' -or
        $ErrorText -match 'Connection refused' -or
        $ErrorText -match 'Connection timed out|No route to host' -or
        $ErrorText -match 'wtw-pwsh-not-found' -or
        $ErrorText -match 'command not found: pwsh|pwsh: command not found' -or
        $ErrorText -match "'pwsh' is not recognized")
}

function Format-WtwSshError {
    <#
    .SYNOPSIS
        Turn a raw ssh failure into something actionable.
    .DESCRIPTION
        wtw connects with BatchMode=yes so a hung prompt can never block a
        command — which means ssh's interactive remedies never appear. The two
        that actually happen on a LAN both look like a bare one-line failure, so
        they get translated here.
    .PARAMETER HostEntry
        Host entry, used to name the fix commands.
    .PARAMETER ErrorText
        Raw stderr from ssh.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [Parameter(Mandatory)] [string] $ErrorText
    )

    $text = $ErrorText.Trim()

    if ($text -match 'Host key verification failed') {
        return @(
            "ssh could not verify the host key for '$($HostEntry.Name)'."
            "This is expected the first time you reach a machine by a new name — the key is"
            "trusted per address, so switching to an mDNS name needs it accepted again."
            "Fix:  wtw host trust $($HostEntry.Name)      (shows fingerprints, asks first)"
            "  or: ssh $($HostEntry.Name)                 (accept the prompt once)"
        ) -join "`n"
    }

    if ($text -match 'Permission denied') {
        return @(
            "ssh was refused by '$($HostEntry.Name)' ($($HostEntry.User)@$($HostEntry.HostName))."
            "Check the key is authorised there, or set one: wtw host add $($HostEntry.Name) --identity <path>"
        ) -join "`n"
    }

    if ($text -match 'Could not resolve hostname|Name or service not known') {
        return "ssh cannot resolve '$($HostEntry.HostName)'. Candidates: $((@($HostEntry.HostNames)) -join ', '). Re-probe with: wtw host sync"
    }

    if ($text -match 'wtw-pwsh-not-found' -or $text -match 'command not found: pwsh' -or $text -match 'pwsh: command not found' -or $text -match "'pwsh' is not recognized") {
        return @(
            "PowerShell (pwsh) was not found on '$($HostEntry.Name)'."
            "wtw drives the remote through pwsh, and an ssh command runs a non-login shell —"
            "so a PATH set up in ~/.zprofile or ~/.bashrc does not apply."
            "  Install it:   brew install powershell   |   winget install Microsoft.PowerShell"
            "  Already installed? Point wtw at it directly:"
            "    wtw host add $($HostEntry.Name) --pwsh /full/path/to/pwsh"
            "  Find the path on that machine with:  which pwsh"
        ) -join "`n"
    }

    if ($text -match 'Connection refused') {
        return @(
            "'$($HostEntry.HostName)' is reachable but nothing is listening on ssh."
            "The machine is up; its ssh *server* is off."
            "  macOS:   System Settings -> General -> Sharing -> Remote Login = On"
            "  Windows: Start-Service sshd   (and Set-Service sshd -StartupType Automatic)"
            "  Linux:   sudo systemctl enable --now ssh"
        ) -join "`n"
    }

    if ($text -match 'Connection timed out|No route to host') {
        return "No answer from '$($HostEntry.HostName)'. Is the machine awake and on the same network? Re-probe with: wtw host sync"
    }

    return "ssh to '$($HostEntry.Name)' failed: $text"
}

function New-WtwRemotePwshCommand {
    <#
    .SYNOPSIS
        Build the remote-side command that runs pwsh with an encoded payload.
    .DESCRIPTION
        `ssh host <command>` runs a NON-login, NON-interactive shell. zsh reads
        only ~/.zshenv then, and Homebrew puts its PATH export in ~/.zprofile —
        so on an Apple-Silicon Mac `pwsh` lives at /opt/homebrew/bin/pwsh and is
        simply not on PATH, giving "command not found: pwsh" even though an
        interactive ssh session finds it fine. /etc/paths does not list Homebrew
        either, so a login shell is not a reliable fix.

        POSIX remotes therefore get a tiny sh loop that tries the known install
        locations and execs the first hit. It is written without a single quote
        character: the whole thing crosses PowerShell argument binding, ssh's
        argv concatenation and the remote shell's parser, and every quote is one
        more thing to be mangled on the way. Base64 is likewise quote-free.

        Windows remotes keep the plain form — cmd.exe cannot run the sh loop, and
        PowerShell there is always on PATH.
    .PARAMETER Encoded
        Base64 (UTF-16LE) payload for -EncodedCommand.
    .PARAMETER HostEntry
        Host entry; supplies Platform and an optional explicit Pwsh path.
    .OUTPUTS
        String[] to append to the ssh argument list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Encoded,
        [Parameter(Mandatory)] $HostEntry,
        [switch] $Interactive
    )

    $explicit = Get-WtwPropertyValue -Object $HostEntry -Name 'Pwsh'

    # Interactive sessions keep the remote profile — the point is to land in a
    # normal shell with the prompt and aliases you would get by hand — and add
    # -NoExit so pwsh stays after running the Set-Location payload.
    $flags = if ($Interactive) { @('-NoLogo', '-NoExit') } else { @('-NoLogo', '-NoProfile') }

    if ($HostEntry.Platform -ieq 'windows') {
        $exe = if ($explicit) { $explicit } else { 'pwsh' }
        return @($exe) + $flags + @('-EncodedCommand', $Encoded)
    }

    $candidates = @()
    if ($explicit) { $candidates += $explicit }
    $candidates += @(
        'pwsh'
        '/opt/homebrew/bin/pwsh'          # Apple Silicon Homebrew
        '/usr/local/bin/pwsh'             # Intel Homebrew, manual installs
        '/usr/bin/pwsh'                   # distro packages
        '/snap/bin/pwsh'
        '$HOME/.dotnet/tools/pwsh'        # dotnet global tool
    )

    # Assembled from single-quoted pieces on purpose: `$c` and `$HOME` belong to
    # the REMOTE shell, and a double-quoted PowerShell string would expand them
    # here (to nothing) before ssh ever saw them.
    $loop = 'for c in ' + ($candidates -join ' ') +
    '; do command -v $c >/dev/null 2>&1 && exec $c ' + ($flags -join ' ') + ' -EncodedCommand ' + $Encoded +
    '; done; echo wtw-pwsh-not-found >&2; exit 127'

    # Comma operator: a bare `return @(...)` unrolls this single-element array to
    # the string itself, and the caller's `+` would then splat it per character.
    return , @($loop)
}

function Write-WtwSshFailure {
    <#
    .SYNOPSIS
        Print an ssh failure as readable lines.
    .DESCRIPTION
        Write-Error and Write-Warning reflow embedded newlines into a single
        wrapped paragraph, which turns a copy-pasteable fix command into prose.
        The guidance goes to the host line by line; the caller still raises a
        short error so exit codes and -ErrorAction keep working.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [Parameter(Mandatory)] [string] $ErrorText
    )

    Write-Host ''
    foreach ($line in (Format-WtwSshError -HostEntry $HostEntry -ErrorText $ErrorText) -split "`n") {
        $color = if ($line -match '^\s*(Fix:|or:|  macOS:|  Windows:|  Linux:|wtw |ssh )') { 'Cyan' } else { 'Yellow' }
        Write-Host "  $line" -ForegroundColor $color
    }
    Write-Host ''
}

function New-WtwRemoteScript {
    <#
    .SYNOPSIS
        Build the PowerShell wtw invokes on the remote machine.
    .DESCRIPTION
        Deliberately does NOT call the remote's `wtw` command. On Windows that
        name resolves to the cmd.exe shim, which treats any subcommand it does
        not recognise as a `go` target — so `wtw __aliases` came back as
        'could not resolve "__aliases"' instead of the registry dump.

        Importing the module and calling Invoke-Wtw directly skips the shim, the
        remote profile, and any shell-specific aliasing. `~/.wtw/module` is where
        `wtw install` puts it; a PSGallery install is the fallback.
    .PARAMETER Arguments
        wtw arguments, e.g. @('__resolve_json', 'auth').
    .PARAMETER WtwCommand
        Optional override from the host config. When set to anything other than
        the default, that command is invoked verbatim instead — an escape hatch
        for non-standard remote installs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Arguments,
        [string] $WtwCommand,
        [string] $WorkingDirectory
    )

    $quoted = @($Arguments | ForEach-Object { "'" + ([string]$_).Replace("'", "''") + "'" }) -join ' '

    # `ssh host <cmd>` starts in the remote home directory, but repo-scoped
    # commands (init, create, add) only mean anything inside the repo.
    $cd = if ($WorkingDirectory) {
        "Set-Location -LiteralPath '" + $WorkingDirectory.Replace("'", "''") + "'`n"
    } else { '' }

    if ($WtwCommand -and $WtwCommand -ne 'wtw') {
        return "$cd$WtwCommand $quoted"
    }

    # OutputRendering=Ansi: without it PowerShell strips colour the moment stdout
    # is not a terminal, and ssh without a TTY is never a terminal — so a
    # delegated `wtw list` would come back monochrome. Forcing Ansi keeps the
    # remote's own rendering (including the colour swatches) intact.
    # WTW_NO_UPDATE_NOTICE: the remote would otherwise prepend its "newer version
    # available" hint to output we are about to parse or print.
    $prelude = @'
$ErrorActionPreference = 'Stop'
$env:WTW_NO_UPDATE_NOTICE = '1'
if ($PSStyle) { $PSStyle.OutputRendering = 'Ansi' }
$wtwModule = Join-Path $HOME '.wtw' 'module' 'wtw.psm1'
if (Test-Path $wtwModule) {
    Import-Module $wtwModule -Force -DisableNameChecking
} else {
    Import-Module wtw -DisableNameChecking
}
'@
    return "$prelude`n$cd" + "Invoke-Wtw $quoted"
}

function Invoke-WtwRemoteCommand {
    <#
    .SYNOPSIS
        Run a wtw subcommand on a remote host over SSH.
    .DESCRIPTION
        The remote machine already runs wtw, and its registry is the only thing
        that knows where a worktree currently lives over there. Rather than
        mirroring that state locally (which would go stale the moment an agent
        created a worktree), local wtw asks the remote wtw.

        The script travels as -EncodedCommand. ssh concatenates its command
        arguments and hands the result to the remote's *default shell* — cmd.exe
        on Windows — so anything with quotes in it gets reinterpreted on the way
        in. Base64 has no characters cmd.exe or sh treat specially, which makes
        the payload identical on every remote platform.

        -NoProfile keeps a chatty remote profile out of stdout; the internal
        `__*` commands already suppress the update notice for the same reason.
    .PARAMETER HostEntry
        Host entry from Resolve-WtwHost.
    .PARAMETER Arguments
        wtw arguments, e.g. @('__resolve_json', 'auth').
    .OUTPUTS
        @{ Success; Output; Error } — Output is the raw stdout lines.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [string] $WorkingDirectory
    )

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        return @{ Success = $false; Output = @(); Error = 'ssh is not on PATH.' }
    }

    $remoteScript = New-WtwRemoteScript -Arguments $Arguments -WtwCommand $HostEntry.Wtw -WorkingDirectory $WorkingDirectory
    # -EncodedCommand wants UTF-16LE, which is what [Text.Encoding]::Unicode is.
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($remoteScript))

    $sshArgs = @('-o', 'BatchMode=yes', $HostEntry.Name) +
    (New-WtwRemotePwshCommand -Encoded $encoded -HostEntry $HostEntry)

    # `6>$null` is load-bearing. A remote pwsh with redirected streams serialises
    # its *information* stream — everything wtw prints with Write-Host — as a
    # CLIXML blob on stderr, in addition to the plain text already on stdout.
    # Local PowerShell recognises the `#< CLIXML` preamble and rehydrates those
    # records into ITS information stream, which the host then prints. Assignment
    # does not capture stream 6, so the output appeared twice: once echoed by the
    # host, once in the variable. Discarding 6 drops the duplicate; the text we
    # actually want is already on stdout.
    $merged = & ssh @sshArgs 2>&1 6>$null
    $code = $LASTEXITCODE

    $stdout = @($merged | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    $stdErrLines = @($merged |
            Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } |
            ForEach-Object { "$_" } |
            Where-Object { $_ -notmatch '^#< CLIXML' -and $_ -notmatch '^<Objs ' })

    return @{
        Success = ($code -eq 0)
        Output  = $stdout
        Error   = if ($stdErrLines.Count -gt 0) { ($stdErrLines -join "`n").Trim() } else { $null }
    }
}

function Get-WtwRemoteTarget {
    <#
    .SYNOPSIS
        Resolve a worktree name on a remote host to its path + workspace file.
    .DESCRIPTION
        Prefers `wtw __resolve_json`, which returns the workspace file path as
        well. Falls back to the older tab-delimited `__resolve` so a machine
        running a wtw that predates this feature still opens — it just loses the
        `.code-workspace` and opens the folder instead.
    .PARAMETER HostEntry
        Host entry from Resolve-WtwHost.
    .PARAMETER Name
        Target name as the *remote* wtw knows it (its aliases, not ours).
    .OUTPUTS
        @{ Path; Workspace; Color; Title; PrettyName } or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [Parameter(Mandatory)] [string] $Name
    )

    $result = Invoke-WtwRemoteCommand -HostEntry $HostEntry -Arguments @('__resolve_json', $Name)
    if ($result.Success -and $result.Output.Count -gt 0) {
        $json = ($result.Output -join "`n").Trim()
        if ($json.StartsWith('{')) {
            try {
                $parsed = $json | ConvertFrom-Json
                return @{
                    Path       = Get-WtwPropertyValue -Object $parsed -Name 'path'
                    Workspace  = Get-WtwPropertyValue -Object $parsed -Name 'workspace'
                    Color      = Get-WtwPropertyValue -Object $parsed -Name 'color'
                    Title      = Get-WtwPropertyValue -Object $parsed -Name 'title'
                    PrettyName = Get-WtwPropertyValue -Object $parsed -Name 'prettyName'
                }
            } catch {
                Write-Verbose "Remote __resolve_json returned unparseable JSON: $json"
            }
        }
    }

    # Older remote wtw: tab-delimited path\tcolor\ttitle\t...
    $legacy = Invoke-WtwRemoteCommand -HostEntry $HostEntry -Arguments @('__resolve', $Name)
    if (-not $legacy.Success -or $legacy.Output.Count -eq 0) {
        # Surface the ssh failure. Without this, a connection problem was
        # indistinguishable from "that worktree does not exist over there".
        # Only shout about the transport when the transport is what broke. A
        # remote "could not resolve" means the session worked and the name did
        # not — the caller shows the available targets instead, which is a far
        # better answer than a wall of remote stack trace.
        $sshError = if ($legacy.Error) { $legacy.Error } else { $result.Error }
        if (Test-WtwIsSshTransportError -ErrorText $sshError) {
            Write-WtwSshFailure -HostEntry $HostEntry -ErrorText $sshError
        } elseif ($sshError) {
            Write-Verbose "Remote reported: $sshError"
        }
        return $null
    }
    $fields = ($legacy.Output | Select-Object -First 1) -split "`t"
    if (-not $fields[0]) { return $null }

    Write-Host "  Remote wtw predates --on; opening the folder (no workspace file)." -ForegroundColor DarkGray
    return @{
        Path       = $fields[0]
        Workspace  = $null
        Color      = if ($fields.Count -gt 1) { $fields[1] } else { $null }
        Title      = if ($fields.Count -gt 2) { $fields[2] } else { $null }
        PrettyName = $null
    }
}
