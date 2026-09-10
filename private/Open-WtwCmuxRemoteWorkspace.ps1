function Get-WtwCmuxRemoteGoInnerCommand {
    <#
    .SYNOPSIS
        ``wtw --on <host> go [name]`` payload typed into a cmux surface.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $HostSelector,
        [AllowNull()][AllowEmptyString()][string] $Name,
        [string] $Via
    )

    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($part in @('wtw', '--on', $HostSelector)) { $tokens.Add($part) }
    if ($Via) {
        $tokens.Add('--via')
        $tokens.Add($Via)
    }
    $tokens.Add('go')
    if ($Name) { $tokens.Add($Name) }

    $quoted = foreach ($token in $tokens) {
        if ($token -match "[\s'`"]") {
            "'" + $token.Replace("'", "''") + "'"
        } else {
            $token
        }
    }
    return ($quoted -join ' ')
}

function Get-WtwCmuxRemoteGoCommand {
    <#
    .SYNOPSIS
        Local pwsh command that SSHs into a remote wtw target from a cmux surface.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $HostSelector,
        [AllowNull()][AllowEmptyString()][string] $Name,
        [string] $Via
    )

    $inner = Get-WtwCmuxRemoteGoInnerCommand -HostSelector $HostSelector -Name $Name -Via $Via
    return "pwsh -NoLogo -NoExit -Command `"Clear-Host; $inner`""
}

function Resolve-WtwCmuxRemoteSession {
    <#
    .SYNOPSIS
        Title, status, color, and shell command for a cmux remote SSH workspace.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [Parameter(Mandatory)][string] $HostSelector,
        [AllowNull()][AllowEmptyString()][string] $Name,
        [string] $Via
    )

    $label = $HostSelector
    $color = $null
    $statusKey = $HostSelector
    $remotePath = $null

    if ($Name) {
        $remote = Get-WtwRemoteTarget -HostEntry $HostEntry -Name $Name
        if (-not $remote -or -not $remote.Path) {
            return $null
        }
        $remotePath = $remote.Path
        $color = $remote.Color
        $label = if ($remote.PrettyName) { $remote.PrettyName }
        elseif ($remote.Title) { $remote.Title }
        else { $Name }
        $statusKey = if ($remote.Title) { "$HostSelector/$($remote.Title)" } else { "$HostSelector/$Name" }
    }

    $inner = Get-WtwCmuxRemoteGoInnerCommand -HostSelector $HostSelector -Name $Name -Via $Via
    return [PSCustomObject]@{
        PrettyName        = "$(Get-WtwHostTitlePrefix -HostEntry $HostEntry)$label"
        StatusValue       = "wtw-remote: $statusKey"
        Command           = "pwsh -NoLogo -NoExit -Command `"Clear-Host; $inner`""
        TypedCommand      = "Clear-Host; $inner"
        ShellInitCommand  = "clear; $inner"
        Color             = $color
        RemotePath        = $remotePath
    }
}

function Find-WtwCmuxRemoteWorkspace {
    <#
    .SYNOPSIS
        Find a live cmux workspace for a remote SSH session by title or description.
    .DESCRIPTION
        Remote sessions share a local cwd (usually the home directory), so they
        must not be matched by path the way local worktrees are.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $PrettyName,
        [string] $StatusValue
    )

    foreach ($workspace in @(Get-WtwCmuxLiveWorkspaces)) {
        $name = Get-WtwCmuxWorkspaceName -Workspace $workspace
        if ($name -and [string]::Equals($name, $PrettyName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $workspace
        }

        if ($StatusValue) {
            $description = Get-WtwCmuxObjectValue -Object $workspace -Names @(
                'description', 'desc', 'subtitle', 'sidebar.description'
            )
            if ($description -and [string]::Equals("$description", $StatusValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $workspace
            }
        }
    }

    return $null
}

function Open-WtwCmuxRemoteWorkspace {
    <#
    .SYNOPSIS
        Open a local cmux workspace whose terminal is an SSH session to a wtw host.
    .DESCRIPTION
        The cmux window stays on this machine; the surface command is
        ``wtw --on <host> go [name]``, the same interactive session as
        ``wtw --on <host> go``. Omit the target name to land in the remote home
        directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [Parameter(Mandatory)][string] $HostSelector,
        [AllowNull()][AllowEmptyString()][string] $Name,
        [string] $Via,
        [switch] $PrintOnly
    )

    if ($Name) {
        Write-Host "  Resolving '$Name' on $($HostEntry.Name)..." -ForegroundColor DarkGray
    }

    $session = Resolve-WtwCmuxRemoteSession `
        -HostEntry $HostEntry `
        -HostSelector $HostSelector `
        -Name $Name `
        -Via $Via

    if (-not $session) {
        $numericHint = Get-WtwNumericNameHint -Name $Name
        if ($numericHint) { Write-Host "  $numericHint" -ForegroundColor Yellow }
        Show-WtwRemoteTargetSuggestions -HostEntry $HostEntry -Name $Name
        Write-Error "Could not resolve '$Name' on $($HostEntry.Name)."
        return
    }

    $localCwd = if ($HOME -and (Test-Path $HOME)) { [System.IO.Path]::GetFullPath($HOME) } else { (Get-Location).Path }

    if ($PrintOnly) {
        Write-Host "  cmux new-workspace --name $($session.PrettyName) --cwd $localCwd --command $($session.Command)" -ForegroundColor White
        return
    }

    if (-not (Test-WtwCmuxPresent)) {
        Write-Error "cmux is not installed or not on PATH. Install cmux or symlink '/Applications/cmux.app/Contents/Resources/bin/cmux'."
        return
    }

    $existing = Find-WtwCmuxRemoteWorkspace -PrettyName $session.PrettyName -StatusValue $session.StatusValue
    if ($existing) {
        $workspaceRef = Get-WtwCmuxWorkspaceRef -Workspace $existing
        if ($workspaceRef) {
            $selectResult = Invoke-WtwCmuxCommand -ArgumentList @('select-workspace', '--workspace', "$workspaceRef")
            if ($selectResult.ExitCode -eq 0) {
                Set-WtwCmuxWorkspaceMetadata `
                    -WorkspaceRef "$workspaceRef" `
                    -PrettyName $session.PrettyName `
                    -Color $session.Color `
                    -StatusValue $session.StatusValue `
                    -CurrentName (Get-WtwCmuxWorkspaceName -Workspace $existing) `
                    -CurrentColor (Get-WtwCmuxObjectValue -Object $existing -Names @('color', 'workspace.color', 'sidebar.color', 'sidebarState.color'))
                Write-Host "  cmux: selected remote workspace '$($session.PrettyName)'" -ForegroundColor Green
                return
            }
        }
    }

    $cmuxArgs = @(
        'new-workspace',
        '--name', $session.PrettyName,
        '--cwd', $localCwd,
        '--command', $session.Command,
        '--focus', 'true',
        '--description', $session.StatusValue
    )
    $createResult = Invoke-WtwCmuxCommand -ArgumentList $cmuxArgs
    if ($createResult.ExitCode -ne 0) {
        if (Open-WtwCmuxAppleScriptWorkspace -ProjectPath $localCwd -PrettyName $session.PrettyName -InitCommand $session.ShellInitCommand -MatchByNameOnly) {
            if (Test-WtwCmuxSocketPermissionDenied -Output $createResult.Output) {
                Write-Host "  cmux: opened remote session via AppleScript fallback (socket access denied)." -ForegroundColor Green
            } else {
                Write-Host "  cmux: opened remote session via AppleScript fallback." -ForegroundColor Green
            }
            return
        }

        Write-Error "cmux remote workspace create failed: $($createResult.Output)"
        return
    }

    $currentResult = Invoke-WtwCmuxCommand -ArgumentList @('current-workspace')
    $workspaceRef = $null
    if ($currentResult.ExitCode -eq 0) {
        $currentWorkspace = ConvertFrom-WtwCmuxCurrentWorkspaceOutput -Output $currentResult.Output
        if ($currentWorkspace) {
            $workspaceRef = Get-WtwCmuxWorkspaceRef -Workspace $currentWorkspace
        }
    }
    if (-not $workspaceRef) {
        $created = Find-WtwCmuxRemoteWorkspace -PrettyName $session.PrettyName -StatusValue $session.StatusValue
        if ($created) {
            $workspaceRef = Get-WtwCmuxWorkspaceRef -Workspace $created
        }
    }

    Set-WtwCmuxWorkspaceMetadata `
        -WorkspaceRef "$workspaceRef" `
        -PrettyName $session.PrettyName `
        -Color $session.Color `
        -StatusValue $session.StatusValue `
        -CurrentName $session.PrettyName `
        -CurrentColor $null

    $where = if ($session.RemotePath) { $session.RemotePath } else { $HostEntry.Name }
    Write-Host "  cmux: remote session '$($session.PrettyName)' → $where" -ForegroundColor Green
}
