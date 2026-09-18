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

function Get-WtwCmuxRemoteStatusValue {
    <#
    .SYNOPSIS
        Stable ``wtw-remote:`` description that later tabs can parse back into go args.
    .DESCRIPTION
        Host selector and the original ``wtw go`` name are space-separated so a
        title like ``app/auth`` cannot be mistaken for the name you type.
        Older tabs used ``wtw-remote: at/app/auth`` (title after a slash).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $HostSelector,
        [AllowNull()][AllowEmptyString()][string] $Name
    )

    if ($Name) { return "wtw-remote: $HostSelector $Name" }
    return "wtw-remote: $HostSelector"
}

function ConvertFrom-WtwCmuxRemoteStatusValue {
    <#
    .SYNOPSIS
        Parse ``wtw-remote: <host> [<name>]`` or the legacy ``wtw-remote: host/title`` form.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string] $StatusValue)

    if ([string]::IsNullOrWhiteSpace($StatusValue)) { return $null }

    $rest = [string]$StatusValue
    if ($rest.StartsWith('wtw-remote:', [System.StringComparison]::OrdinalIgnoreCase)) {
        $rest = $rest.Substring('wtw-remote:'.Length).Trim()
    } else {
        return $null
    }
    if (-not $rest) { return $null }

    if ($rest -match '^(?<host>\S+)\s+(?<name>.+)$') {
        return [PSCustomObject]@{
            HostSelector = $matches.host
            Name         = $matches.name.Trim()
        }
    }

    if ($rest -match '^(?<host>[^/\s]+)/(?<name>.+)$') {
        return [PSCustomObject]@{
            HostSelector = $matches.host
            Name         = $matches.name.Trim()
        }
    }

    return [PSCustomObject]@{
        HostSelector = $rest
        Name         = ''
    }
}

function Test-WtwCmuxWorkspaceRefMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Workspace,
        [Parameter(Mandatory)][string] $Ref
    )

    foreach ($name in @('ref', 'workspaceRef', 'workspace', 'id', 'uuid', 'workspace_id', 'workspaceId')) {
        $value = Get-WtwCmuxObjectValue -Object $Workspace -Names @($name)
        if ($value -and [string]::Equals("$value", $Ref, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-WtwCmuxWorkspaceByRef {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $WorkspaceRef)

    foreach ($workspace in @(Get-WtwCmuxLiveWorkspaces)) {
        if (Test-WtwCmuxWorkspaceRefMatch -Workspace $workspace -Ref $WorkspaceRef) {
            return $workspace
        }
    }

    return $null
}

function Get-WtwCmuxCurrentWorkspaceObject {
    [CmdletBinding()]
    param()

    $ref = $env:CMUX_WORKSPACE_ID
    if ($ref) {
        $byRef = Get-WtwCmuxWorkspaceByRef -WorkspaceRef $ref
        if ($byRef) { return $byRef }
    }

    $currentResult = Invoke-WtwCmuxCommand -ArgumentList @('current-workspace')
    if ($currentResult.ExitCode -eq 0) {
        $current = ConvertFrom-WtwCmuxCurrentWorkspaceOutput -Output $currentResult.Output
        if ($current) {
            $fromCurrent = $current
            $currentRef = Get-WtwCmuxWorkspaceRef -Workspace $current
            if ($currentRef) {
                $byRef = Get-WtwCmuxWorkspaceByRef -WorkspaceRef $currentRef
                if ($byRef) { return $byRef }
            }
            if (Resolve-WtwCmuxRemoteSessionFromWorkspace -Workspace $fromCurrent) {
                return $fromCurrent
            }
        }
    }

    foreach ($workspace in @(Get-WtwCmuxLiveWorkspaces)) {
        $selected = Get-WtwCmuxObjectValue -Object $workspace -Names @('selected', 'is_selected', 'isSelected')
        if ($selected -eq $true) { return $workspace }
    }

    return $null
}

function Get-WtwCmuxRemoteGoNameFromTitleRest {
    <#
    .SYNOPSIS
        Drop leading glyphs from a host-prefixed title so the go-name remains.
    .DESCRIPTION
        Live titles look like ``🧊AT 🐇 scoring-system-that-works``. After the
        host prefix the worktree emoji is still there; remote ``wtw go`` wants
        ``scoring-system-that-works``.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string] $Rest)

    if ([string]::IsNullOrWhiteSpace($Rest)) { return '' }

    $parts = @($Rest.Trim() -split '\s+' | Where-Object { $_ })
    if ($parts.Count -eq 0) { return '' }

    $index = 0
    while ($index -lt $parts.Count -and $parts[$index] -notmatch '[\p{L}\p{N}]') {
        $index++
    }
    if ($index -ge $parts.Count) { return ($parts[-1]) }
    return ($parts[$index..($parts.Count - 1)] -join ' ')
}

function Resolve-WtwCmuxRemoteSessionFromWorkspace {
    <#
    .SYNOPSIS
        Recover host + go-name from a live cmux workspace when process env is empty.
    .DESCRIPTION
        Older remote tabs were created before ``WTW_REMOTE_*`` was stamped. Those
        still carry a ``wtw-remote:`` description, workspace env, or a title that
        starts with the host prefix (``🧊AT scoring-system-that-works``).
    #>
    [CmdletBinding()]
    param($Workspace)

    if (-not $Workspace) { return $null }

    $envHost = Get-WtwCmuxObjectValue -Object $Workspace -Names @(
        'env.WTW_REMOTE_HOST',
        'environment.WTW_REMOTE_HOST',
        'workspace.env.WTW_REMOTE_HOST'
    )
    if ($envHost) {
        return [PSCustomObject]@{
            HostSelector = [string]$envHost
            Name         = [string](Get-WtwCmuxObjectValue -Object $Workspace -Names @(
                    'env.WTW_REMOTE_NAME',
                    'environment.WTW_REMOTE_NAME',
                    'workspace.env.WTW_REMOTE_NAME'
                ))
        }
    }

    $status = Get-WtwCmuxObjectValue -Object $Workspace -Names @(
        'description', 'desc', 'subtitle', 'sidebar.description', 'status'
    )
    $parsed = ConvertFrom-WtwCmuxRemoteStatusValue -StatusValue $status
    if ($parsed) { return $parsed }

    $title = Get-WtwCmuxWorkspaceName -Workspace $Workspace
    if (-not $title) { return $null }

    foreach ($hostEntry in (Get-WtwHosts)) {
        $prefix = Get-WtwHostTitlePrefix -HostEntry $hostEntry
        if (-not $prefix) { continue }
        if (-not $title.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        $rest = Get-WtwCmuxRemoteGoNameFromTitleRest -Rest ($title.Substring($prefix.Length))
        $known = @(@($hostEntry.Name) + @($hostEntry.Aliases) | Where-Object { $_ })
        $name = if (-not $rest -or ($rest -in $known)) { '' } else { $rest }
        return [PSCustomObject]@{
            HostSelector = [string]$hostEntry.Name
            Name         = $name
        }
    }

    return $null
}

function Get-WtwCmuxCurrentRemoteSession {
    <#
    .SYNOPSIS
        Host + go-name for the current cmux workspace when it is a wtw SSH session.
    .DESCRIPTION
        Prefers ``WTW_REMOTE_HOST`` / ``WTW_REMOTE_NAME`` (set on the workspace
        when it was created, inherited by every new tab). Falls back to the
        workspace object (env, ``wtw-remote:`` description, or host-prefixed
        title) so older tabs and Command Palette actions still SSH.
    #>
    [CmdletBinding()]
    param()

    $hostSelector = $env:WTW_REMOTE_HOST
    $name = $env:WTW_REMOTE_NAME

    if (-not $hostSelector) {
        $parsed = Resolve-WtwCmuxRemoteSessionFromWorkspace -Workspace (Get-WtwCmuxCurrentWorkspaceObject)
        if ($parsed) {
            $hostSelector = $parsed.HostSelector
            $name = $parsed.Name
        }
    }

    if (-not $hostSelector) { return $null }

    $hostEntry = Resolve-WtwHost -Name $hostSelector
    if (-not $hostEntry) { return $null }

    return [PSCustomObject]@{
        HostEntry    = $hostEntry
        HostSelector = $hostSelector
        Name         = $name
    }
}

function Get-WtwCmuxRemoteWorkspaceLayoutJson {
    <#
    .SYNOPSIS
        Two-tab layout: 🌴 wtw and a normal remote pwsh, both SSH into the same target.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Session)

    $layout = [PSCustomObject]@{
        pane = [PSCustomObject]@{
            surfaces = @(
                [PSCustomObject]@{
                    type    = 'terminal'
                    name    = '🌴 wtw'
                    command = $Session.Command
                    focus   = $true
                }
                [PSCustomObject]@{
                    type    = 'terminal'
                    name    = 'pwsh'
                    command = $Session.Command
                }
            )
        }
    }

    return ($layout | ConvertTo-Json -Compress -Depth 8)
}

function Add-WtwCmuxRemoteWorkspaceEnvArgs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[string]] $ArgumentList,
        [Parameter(Mandatory)][string] $HostSelector,
        [AllowNull()][AllowEmptyString()][string] $Name
    )

    [void]$ArgumentList.Add('--env')
    [void]$ArgumentList.Add("WTW_REMOTE_HOST=$HostSelector")
    if ($Name) {
        [void]$ArgumentList.Add('--env')
        [void]$ArgumentList.Add("WTW_REMOTE_NAME=$Name")
    }
}

function Add-WtwCmuxRemoteShellSurface {
    [CmdletBinding()]
    param(
        [string] $WorkspaceRef,
        [Parameter(Mandatory)][string] $Command
    )

    $args = [System.Collections.Generic.List[string]]::new()
    [void]$args.Add('new-surface')
    [void]$args.Add('--type')
    [void]$args.Add('terminal')
    [void]$args.Add('--command')
    [void]$args.Add($Command)
    [void]$args.Add('--focus')
    [void]$args.Add('false')
    if ($WorkspaceRef) {
        [void]$args.Add('--workspace')
        [void]$args.Add($WorkspaceRef)
    }

    Invoke-WtwCmuxCommand -ArgumentList @($args) | Out-Null
}

function Connect-WtwCmuxCurrentRemoteSession {
    <#
    .SYNOPSIS
        SSH into the remote target owned by the current cmux workspace.
    #>
    [CmdletBinding()]
    param()

    $remote = Get-WtwCmuxCurrentRemoteSession
    if (-not $remote) { return $false }

    Connect-WtwRemoteWorktree -HostEntry $remote.HostEntry -Name $remote.Name
    return $true
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
    $remotePath = $null
    $repoName = $null
    $repoEmoji = $null

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
        $repoName = Get-WtwPropertyValue -Object $remote -Name 'Repo'
        $repoEmoji = Get-WtwPropertyValue -Object $remote -Name 'RepoEmoji'
    }

    $inner = Get-WtwCmuxRemoteGoInnerCommand -HostSelector $HostSelector -Name $Name -Via $Via
    return [PSCustomObject]@{
        PrettyName        = "$(Get-WtwHostTitlePrefix -HostEntry $HostEntry)$label"
        StatusValue       = (Get-WtwCmuxRemoteStatusValue -HostSelector $HostSelector -Name $Name)
        Command           = "pwsh -NoLogo -NoExit -Command `"Clear-Host; $inner`""
        TypedCommand      = "Clear-Host; $inner"
        ShellInitCommand  = "clear; $inner"
        Color             = $color
        RemotePath        = $remotePath
        HostSelector      = $HostSelector
        Name              = $Name
        RepoName          = $repoName
        RepoEmoji         = $repoEmoji
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
                'description', 'desc', 'subtitle', 'sidebar.description', 'status'
            )
            if ($description -and [string]::Equals("$description", $StatusValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $workspace
            }

            $wanted = ConvertFrom-WtwCmuxRemoteStatusValue -StatusValue $StatusValue
            $have = ConvertFrom-WtwCmuxRemoteStatusValue -StatusValue $description
            if (
                $wanted -and $have -and
                [string]::Equals($wanted.HostSelector, $have.HostSelector, [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals("$($wanted.Name)", "$($have.Name)", [System.StringComparison]::OrdinalIgnoreCase)
            ) {
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
        The cmux window stays on this machine. The workspace opens two tabs —
        🌴 wtw and a normal remote pwsh — both running
        ``wtw --on <host> go [name]``. Extra 🌴 wtw / pwsh Command Palette
        actions in that workspace SSH to the same target (they inherit
        ``WTW_REMOTE_HOST`` / ``WTW_REMOTE_NAME``). Omit the target name to
        land in the remote home directory.
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
        Write-WtwHost "  Resolving '$Name' on $($HostEntry.Name)..." -ForegroundColor DarkGray
    }

    $session = Resolve-WtwCmuxRemoteSession `
        -HostEntry $HostEntry `
        -HostSelector $HostSelector `
        -Name $Name `
        -Via $Via

    if (-not $session) {
        $numericHint = Get-WtwNumericNameHint -Name $Name
        if ($numericHint) { Write-WtwHost "  $numericHint" -ForegroundColor Yellow }
        Show-WtwRemoteTargetSuggestions -HostEntry $HostEntry -Name $Name
        Write-Error "Could not resolve '$Name' on $($HostEntry.Name)."
        return
    }

    $localCwd = if ($HOME -and (Test-Path $HOME)) { [System.IO.Path]::GetFullPath($HOME) } else { (Get-Location).Path }

    if ($PrintOnly) {
        $layout = Get-WtwCmuxRemoteWorkspaceLayoutJson -Session $session
        Write-WtwHost "  cmux new-workspace --name $($session.PrettyName) --cwd $localCwd --description $($session.StatusValue) --layout $layout" -ForegroundColor White
        return
    }

    if (-not (Test-WtwCmuxPresent)) {
        Write-Error "cmux is not installed or not on PATH. Install cmux or symlink '/Applications/cmux.app/Contents/Resources/bin/cmux'."
        return
    }

    # Machine-level project (sidebar / Command Palette), independent of this
    # invocation's optional worktree name. Opening `wtw --on at cmux auth`
    # still creates the live auth tab; the host project stays `wtw --on at go`.
    Register-WtwCmuxRemoteProject -HostEntry $HostEntry -HostSelector $HostSelector | Out-Null

    $groupSpec = Get-WtwCmuxRemoteWorkspaceGroupSpec -HostEntry $HostEntry -Session $session
    $group = Ensure-WtwCmuxWorkspaceGroup -Spec $groupSpec

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
                Add-WtwCmuxWorkspaceToGroup -Group $group -WorkspaceRef "$workspaceRef"
                Write-WtwHost "  cmux: selected remote workspace '$($session.PrettyName)' ($($groupSpec.Name))" -ForegroundColor Green
                return
            }
        }
    }

    $layout = Get-WtwCmuxRemoteWorkspaceLayoutJson -Session $session
    $cmuxArgs = [System.Collections.Generic.List[string]]::new()
    foreach ($part in @(
            'new-workspace',
            '--name', $session.PrettyName,
            '--cwd', $localCwd,
            '--layout', $layout,
            '--focus', 'true',
            '--description', $session.StatusValue
        )) {
        [void]$cmuxArgs.Add($part)
    }
    foreach ($part in @(Get-WtwCmuxNewWorkspaceGroupArgs -Group $group)) {
        [void]$cmuxArgs.Add($part)
    }
    Add-WtwCmuxRemoteWorkspaceEnvArgs -ArgumentList $cmuxArgs -HostSelector $HostSelector -Name $Name

    $createResult = Invoke-WtwCmuxCommand -ArgumentList @($cmuxArgs)
    $usedSingleCommand = $false
    if ($createResult.ExitCode -ne 0) {
        $fallbackArgs = [System.Collections.Generic.List[string]]::new()
        foreach ($part in @(
                'new-workspace',
                '--name', $session.PrettyName,
                '--cwd', $localCwd,
                '--command', $session.Command,
                '--focus', 'true',
                '--description', $session.StatusValue
            )) {
            [void]$fallbackArgs.Add($part)
        }
        foreach ($part in @(Get-WtwCmuxNewWorkspaceGroupArgs -Group $group)) {
            [void]$fallbackArgs.Add($part)
        }
        Add-WtwCmuxRemoteWorkspaceEnvArgs -ArgumentList $fallbackArgs -HostSelector $HostSelector -Name $Name
        $createResult = Invoke-WtwCmuxCommand -ArgumentList @($fallbackArgs)
        $usedSingleCommand = $true
    }
    if ($createResult.ExitCode -ne 0 -and $group) {
        $plainArgs = [System.Collections.Generic.List[string]]::new()
        foreach ($part in $cmuxArgs) {
            if ($part -in @('--group', $group.Ref)) { continue }
            [void]$plainArgs.Add($part)
        }
        $createResult = Invoke-WtwCmuxCommand -ArgumentList @($plainArgs)
    }
    if ($createResult.ExitCode -ne 0) {
        if (Open-WtwCmuxAppleScriptWorkspace -ProjectPath $localCwd -PrettyName $session.PrettyName -InitCommand $session.ShellInitCommand -MatchByNameOnly) {
            if (Test-WtwCmuxSocketPermissionDenied -Output $createResult.Output) {
                Write-WtwHost "  cmux: opened remote session via AppleScript fallback (socket access denied)." -ForegroundColor Green
            } else {
                Write-WtwHost "  cmux: opened remote session via AppleScript fallback." -ForegroundColor Green
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

    if ($usedSingleCommand) {
        Add-WtwCmuxRemoteShellSurface -WorkspaceRef $workspaceRef -Command $session.Command
    }

    Add-WtwCmuxWorkspaceToGroup -Group $group -WorkspaceRef "$workspaceRef"

    $where = if ($session.RemotePath) { $session.RemotePath } else { $HostEntry.Name }
    Write-WtwHost "  cmux: remote session '$($session.PrettyName)' → $where ($($groupSpec.Name))" -ForegroundColor Green
}
