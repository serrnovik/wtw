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

    if (-not $SkipChecks -and -not (Test-WtwSshHostKnown -Name $HostEntry.Name)) {
        Write-Host "  '$($HostEntry.Name)' is not resolvable by the ssh client — the editor resolves the host itself, not through wtw." -ForegroundColor Yellow
        Write-Host "  Fix: wtw host sync" -ForegroundColor DarkGray
    }

    Write-Host "  Resolving '$Name' on $($HostEntry.Name)..." -ForegroundColor DarkGray
    $remote = Get-WtwRemoteTarget -HostEntry $HostEntry -Name $Name
    if (-not $remote -or -not $remote.Path) {
        # Deliberately does not assert the target is missing — a connection
        # failure lands here too, and Get-WtwRemoteTarget has already warned with
        # the ssh reason when that is what happened.
        Write-Error "Could not resolve '$Name' on $($HostEntry.Name). If the warning above names an ssh problem, fix that first; otherwise check the name exists there: wtw list --on $($HostEntry.Name)"
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
