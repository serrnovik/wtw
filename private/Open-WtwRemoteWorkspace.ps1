function Resolve-WtwRemoteLaunch {
    <#
    .SYNOPSIS
        Build the editor invocation for a remote worktree, without running it.
    .DESCRIPTION
        Split out from Open-WtwRemoteWorkspace so the exact command line is
        testable and printable (`--print-only`) without an SSH round trip or a
        running editor.

        A workspace file is opened via --file-uri and a bare directory via
        --folder-uri; both carry the full `vscode-remote://ssh-remote+host/…`
        authority, which is what makes the editor attach to the remote rather
        than looking for the path locally.
    .PARAMETER Editor
        Logical editor name ('cursor').
    .PARAMETER HostEntry
        Host entry from Resolve-WtwHost.
    .PARAMETER RemoteTarget
        Result of Get-WtwRemoteTarget.
    .PARAMETER Folder
        Force folder-open even when a workspace file exists.
    .OUTPUTS
        @{ Editor; PreArgs; Uri; Kind }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Editor,
        [Parameter(Mandatory)] $HostEntry,
        [Parameter(Mandatory)] $RemoteTarget,
        [switch] $Folder
    )

    $useWorkspace = (-not $Folder) -and $RemoteTarget.Workspace
    $path = if ($useWorkspace) { $RemoteTarget.Workspace } else { $RemoteTarget.Path }
    $uri = ConvertTo-WtwRemoteUri -Path $path -HostName $HostEntry.Name -Platform $HostEntry.Platform
    $flag = if ($useWorkspace) { '--file-uri' } else { '--folder-uri' }

    return @{
        Editor  = $Editor
        PreArgs = @($flag, $uri)
        Uri     = $uri
        Kind    = if ($useWorkspace) { 'workspace' } else { 'folder' }
    }
}

function Open-WtwRemoteWorkspace {
    <#
    .SYNOPSIS
        Open a worktree that lives on another machine, over Remote-SSH.
    .DESCRIPTION
        The local half of `wtw --on <host> <editor> <name>`. wtw does not create,
        move, or mirror anything on the remote — the worktree is already there,
        made by whatever agent is working on that box. This only discovers where
        it is and points a local editor window at it.

        Order matters. The ssh config check comes before the extension check,
        which comes before launch, because each failure is progressively more
        confusing to diagnose from the editor's own error message.
    .PARAMETER HostEntry
        Host entry from Resolve-WtwHost.
    .PARAMETER Name
        Target name as the remote wtw knows it.
    .PARAMETER Editor
        Logical editor name. Must be a VS Code family member.
    .PARAMETER Folder
        Open the directory even when a .code-workspace exists remotely.
    .PARAMETER PrintOnly
        Print the resolved command instead of launching.
    .PARAMETER SkipChecks
        Skip the ssh-config / extension / settings preflight.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Editor,
        [switch] $Folder,
        [switch] $PrintOnly,
        [switch] $SkipChecks
    )

    $member = Get-WtwEditorFamilyMember -Id $Editor
    if (-not $member) {
        Write-Error "'$Editor' cannot open a remote worktree. Remote opening needs a VS Code family editor ($((Get-WtwEditorFamily | ForEach-Object { $_.Id }) -join ', ')) — other targets register project state on the machine they run on, so run wtw on $($HostEntry.Name) for those."
        return
    }

    # A --via override targets a raw address on purpose, and `ssh -G 1.2.3.4`
    # echoing the address back is correct, not a missing config — so the
    # "not resolvable" warning would be pure noise there.
    $viaOverride = Get-WtwPropertyValue -Object $HostEntry -Name 'ViaOverride'
    if (-not $SkipChecks -and -not $viaOverride -and -not (Test-WtwSshHostKnown -Name $HostEntry.Name)) {
        Write-Host "  '$($HostEntry.Name)' is not resolvable by the ssh client — the editor resolves the host itself, not through wtw." -ForegroundColor Yellow
        Write-Host "  Fix: wtw host sync" -ForegroundColor DarkGray
    }

    Write-Host "  Resolving '$Name' on $($HostEntry.Name)..." -ForegroundColor DarkGray
    $remote = Get-WtwRemoteTarget -HostEntry $HostEntry -Name $Name
    if (-not $remote -or -not $remote.Path) {
        $numericHint = Get-WtwNumericNameHint -Name $Name
        if ($numericHint) { Write-Host "  $numericHint" -ForegroundColor Yellow }
        Show-WtwRemoteTargetSuggestions -HostEntry $HostEntry -Name $Name
        # Deliberately does not assert the target is missing — a connection
        # failure lands here too, and Get-WtwRemoteTarget has already warned with
        # the ssh reason when that is what happened.
        Write-Error "Could not resolve '$Name' on $($HostEntry.Name)."
        return
    }

    $launch = Resolve-WtwRemoteLaunch -Editor $Editor -HostEntry $HostEntry -RemoteTarget $remote -Folder:$Folder

    if ($PrintOnly) {
        $preview = Invoke-WtwEditorCli -Cmd $Editor -PreArgs $launch.PreArgs -PassThru
        if ($preview) {
            Write-Host "  $($preview.Exe) $($preview.Arguments -join ' ')" -ForegroundColor White
        } else {
            Write-Host "  <$Editor CLI not found> $($launch.PreArgs -join ' ')" -ForegroundColor Yellow
        }
        return
    }

    if (-not $SkipChecks) {
        if (-not (Test-WtwRemoteExtension -Cmd $Editor -Quiet)) {
            Write-Host "  Continuing anyway — the editor will prompt if it cannot attach." -ForegroundColor DarkGray
        }
        Set-WtwRemotePlatform -Cmd $Editor -HostName $HostEntry.Name -Platform $HostEntry.Platform | Out-Null
    }

    $label = if ($remote.Title) { $remote.Title } else { $Name }
    Write-Host "  Opening $label on $($HostEntry.Name) in ${Editor}: $($remote.Path)" -ForegroundColor Green
    Invoke-WtwEditorCli -Cmd $Editor -PreArgs $launch.PreArgs
}

function Show-WtwRemoteTargetSuggestions {
    <#
    .SYNOPSIS
        After a failed remote resolve, show what that machine actually has.
    .DESCRIPTION
        The remote's own "could not resolve" message ends with "run wtw list",
        which is fine locally and unhelpful across a network — you cannot glance
        at the other machine's registry. One extra round trip on a failure path
        turns a dead end into an answer.

        Prefers targets that contain the searched text, or its digits when the
        name is something like PF033: a wrong issue number is the common case,
        and "here are the ones with 03 in them" is the useful reply. Falls back
        to the full list when nothing is close.
    .PARAMETER HostEntry
        Host entry from Resolve-WtwHost.
    .PARAMETER Name
        The name that failed to resolve.
    .PARAMETER Max
        Cap on how many names to print.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [Parameter(Mandatory)] [string] $Name,
        [int] $Max = 15
    )

    $result = Invoke-WtwRemoteCommand -HostEntry $HostEntry -Arguments @('__aliases')
    if (-not $result.Success) { return }

    $aliases = @($result.Output |
            Where-Object { $_ } |
            ForEach-Object { ($_ -split "`t")[0] } |
            Where-Object { $_ } |
            Sort-Object -Unique)
    if ($aliases.Count -eq 0) { return }

    $close = @($aliases | Where-Object { $_ -like "*$Name*" })

    # Token-level near match. Whole-string edit distance is useless here:
    # 'PF033' is ~30 edits from 'sn-PF037_gamification_and_virality', so the
    # normal fuzzy pass cannot see it — but it is ONE edit from that name's
    # 'PF037' token, which is exactly the mistake being made (wrong issue
    # number). Suggest it; never auto-resolve it, because silently opening a
    # different issue's worktree is worse than saying nothing.
    if ($close.Count -eq 0) {
        $close = @($aliases | Where-Object {
                $tokens = @($_ -split '[^A-Za-z0-9]+' | Where-Object { $_ })
                @($tokens | Where-Object {
                        $budget = [Math]::Max(1, [Math]::Floor($Name.Length / 4))
                        (Get-WtwEditDistance $Name $_) -le $budget
                    }).Count -gt 0
            })
    }

    if ($close.Count -eq 0) {
        $digits = ([regex]::Match($Name, '\d+')).Value
        if ($digits) { $close = @($aliases | Where-Object { $_ -match $digits }) }
    }

    Write-Host ''
    if ($close.Count -gt 0) {
        Write-Host "  Closest on $($HostEntry.Name):" -ForegroundColor Cyan
        foreach ($a in ($close | Select-Object -First $Max)) { Write-Host "    $a" -ForegroundColor White }
    } else {
        Write-Host "  Nothing on $($HostEntry.Name) matches '$Name'. It has:" -ForegroundColor Yellow
        foreach ($a in ($aliases | Select-Object -First $Max)) { Write-Host "    $a" -ForegroundColor DarkGray }
        if ($aliases.Count -gt $Max) { Write-Host "    … and $($aliases.Count - $Max) more (wtw list --on $($HostEntry.Name))" -ForegroundColor DarkGray }
    }
    Write-Host ''
}

function Invoke-WtwRemoteWtw {
    <#
    .SYNOPSIS
        Run a wtw command on the remote and print its output verbatim.
    .DESCRIPTION
        The escape hatch for everything wtw cannot meaningfully do from here.
        `wtw --on <host> create x` or `wtw --on <host> run <anything>` executes on
        the machine that owns the worktrees, so its registry stays authoritative —
        which was the original reason those commands were refused. Refusing them
        outright was too strict: running them *there* is exactly right, it just
        has to actually happen there.

        Output is printed rather than parsed, and arrives with its ANSI colour
        intact because the remote script forces OutputRendering=Ansi.
    .PARAMETER HostEntry
        Host entry from Resolve-WtwHost.
    .PARAMETER Arguments
        Full wtw argument list, e.g. @('create','auth').
    .PARAMETER WorkingDirectory
        Remote directory to run in. Repo-scoped commands (init, add, create) need
        this — an ssh command starts in the remote home directory.
    .PARAMETER Title
        Header shown above the output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [string] $WorkingDirectory,
        [string] $Title
    )

    $result = Invoke-WtwRemoteCommand -HostEntry $HostEntry -Arguments $Arguments -WorkingDirectory $WorkingDirectory

    Write-Host ''
    if ($Title) { Write-Host "  $Title" -ForegroundColor Cyan }

    foreach ($line in $result.Output) {
        # Strip CR so a Windows remote leaves no stray carriage returns; write
        # raw so embedded ANSI colour survives.
        Write-Host ($line -replace "`r", '')
    }

    if (-not $result.Success) {
        if ($result.Error) {
            Write-WtwSshFailure -HostEntry $HostEntry -ErrorText $result.Error
        }
        Write-Error "Command failed on $($HostEntry.Name)."
        return
    }
    Write-Host ''
}

function Get-WtwRemoteList {
    <#
    .SYNOPSIS
        Show the remote machine's `wtw list`, rendered by the remote itself.
    .DESCRIPTION
        Delegates rather than reimplements. An earlier version parsed the
        machine-readable `__aliases` dump and drew its own table, which meant
        every flag had to be re-supported by hand — `--detailed` was silently
        ignored — and the colour swatches were lost.

        Running the remote's own `wtw list <flags>` gives exact parity: every
        flag behaves as it does locally because it is parsed by the same CLI, and
        the output arrives with its ANSI colour intact (the remote script forces
        OutputRendering=Ansi, since ssh without a TTY is not a terminal).
    .PARAMETER HostEntry
        Host entry from Resolve-WtwHost.
    .PARAMETER Arguments
        Flags to forward verbatim, e.g. @('--detailed') or @('--wide','--repo','sn').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [string[]] $Arguments = @()
    )

    $result = Invoke-WtwRemoteCommand -HostEntry $HostEntry -Arguments (@('list') + @($Arguments))
    if (-not $result.Success) {
        # Route through Format-WtwSshError like every other remote entry point:
        # the raw one-liner ("Host key verification failed.") names the symptom
        # but not the fix, and BatchMode means ssh never offers its own.
        if ($result.Error) {
            Write-WtwSshFailure -HostEntry $HostEntry -ErrorText $result.Error
        } else {
            Write-Host "  No output and no error text — is pwsh installed on $($HostEntry.Name)?" -ForegroundColor Yellow
        }
        Write-Error "Could not reach wtw on $($HostEntry.Name)."
        return
    }

    Write-Host ''
    Write-Host "  wtw on $($HostEntry.Name)" -ForegroundColor Cyan

    foreach ($line in $result.Output) {
        # Strip CR so a Windows remote does not leave stray carriage returns
        # mid-line; write raw so embedded ANSI colour survives.
        Write-Host ($line -replace "`r", '')
    }

    Write-Host "  Open one:  wtw --on $($HostEntry.Name) cursor <alias>" -ForegroundColor DarkGray
    Write-Host ''
}
