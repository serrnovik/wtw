function Get-WtwCmuxObjectValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)][string[]] $Names
    )

    foreach ($name in $Names) {
        $current = $Object
        $found = $true
        foreach ($part in $name.Split('.')) {
            if (-not $current) { $found = $false; break }
            $prop = $current.PSObject.Properties[$part]
            if (-not $prop) { $found = $false; break }
            $current = $prop.Value
        }
        if ($found -and $null -ne $current -and "$current" -ne '') { return $current }
    }

    return $null
}

function Get-WtwCmuxWorkspaceRef {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Workspace)

    return Get-WtwCmuxObjectValue -Object $Workspace -Names @(
        'ref',
        'workspaceRef',
        'workspace',
        'id',
        'uuid',
        'workspace_id',
        'workspaceId',
        'refs.workspace',
        'refs.workspaceRef'
    )
}

function Get-WtwCmuxWorkspaceName {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Workspace)

    return Get-WtwCmuxObjectValue -Object $Workspace -Names @('name', 'title', 'displayName')
}

function Get-WtwCmuxWorkspaceCwd {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Workspace)

    return Get-WtwCmuxObjectValue -Object $Workspace -Names @(
        'cwd',
        'path',
        'current_directory',
        'workingDirectory',
        'currentWorkingDirectory',
        'sidebar.cwd',
        'sidebarState.cwd'
    )
}

function Get-WtwCmuxLiveWorkspaces {
    [CmdletBinding()]
    param()

    $result = Invoke-WtwCmuxCommand -ArgumentList @('list-workspaces', '--json')
    if ($result.ExitCode -ne 0) { return @() }

    $parsed = ConvertFrom-WtwCmuxJsonOutput -Output $result.Output
    if ($parsed) {
        if ($parsed -is [array]) { return @($parsed) }
        if ((Get-WtwPropertyNames -Object $parsed) -contains 'workspaces') { return @($parsed.workspaces) }
        return @($parsed)
    }

    $fallbackResult = Invoke-WtwCmuxCommand -ArgumentList @('list-workspaces')
    if ($fallbackResult.ExitCode -ne 0) { return @() }
    return ConvertFrom-WtwCmuxWorkspaceListOutput -Output $fallbackResult.Output
}

function Find-WtwCmuxWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName
    )

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $workspaces = @(Get-WtwCmuxLiveWorkspaces)
    if ($workspaces.Count -eq 0) { return $null }

    $byCwd = $workspaces | Where-Object {
        $cwd = Get-WtwCmuxWorkspaceCwd -Workspace $_
        $cwd -and [string]::Equals([System.IO.Path]::GetFullPath("$cwd"), $fullPath, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1
    if ($byCwd) { return $byCwd }

    return $workspaces | Where-Object {
        [string]::Equals((Get-WtwCmuxWorkspaceName -Workspace $_), $PrettyName, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1
}

function Set-WtwCmuxWorkspaceMetadata {
    [CmdletBinding()]
    param(
        [string] $WorkspaceRef,
        [string] $PrettyName,
        [string] $Color,
        [string] $StatusValue,
        [string] $CurrentName,
        [string] $CurrentColor
    )

    if (-not $WorkspaceRef) { return }

    if ($PrettyName -and -not [string]::Equals($CurrentName, $PrettyName, [System.StringComparison]::Ordinal)) {
        Invoke-WtwCmuxCommand -ArgumentList @('workspace-action', '--workspace', $WorkspaceRef, '--action', 'rename', '--title', $PrettyName) | Out-Null
    }
    if ($Color -and -not [string]::Equals($CurrentColor, $Color, [System.StringComparison]::OrdinalIgnoreCase)) {
        Invoke-WtwCmuxCommand -ArgumentList @('workspace-action', '--workspace', $WorkspaceRef, '--action', 'set-color', '--color', $Color) | Out-Null
    }
    if ($StatusValue) {
        $statusColor = if ([string]::IsNullOrWhiteSpace($Color)) { '#7A4FD8' } else { $Color }
        Invoke-WtwCmuxCommand -ArgumentList @('set-status', 'wtw', $StatusValue, '--workspace', $WorkspaceRef, '--icon', 'git-branch', '--color', $statusColor, '--priority', '90') | Out-Null
    }
}

function Test-WtwCmuxSocketPermissionDenied {
    [CmdletBinding()]
    param([string] $Output)

    if ([string]::IsNullOrWhiteSpace($Output)) { return $false }

    return (
        $Output -match 'Access denied' -or
        $Output -match 'Operation not permitted' -or
        $Output -match 'only processes started inside cmux can connect'
    )
}

function ConvertTo-WtwPowerShellSingleQuotedLiteral {
    [CmdletBinding()]
    param([AllowNull()][string] $Value)

    return "'$($Value.Replace("'", "''"))'"
}

function ConvertTo-WtwPosixSingleQuotedLiteral {
    [CmdletBinding()]
    param([AllowNull()][string] $Value)

    if ($null -eq $Value) { return "''" }
    return "'" + $Value.Replace("'", "'\''") + "'"
}

function Get-WtwCmuxLocalAppleScriptInitCommand {
    <#
    .SYNOPSIS
        POSIX command typed into cmux's default macOS tab during AppleScript fallback.
    .DESCRIPTION
        cmux's default surface is zsh. Do not type PowerShell (Set-Location / Clear-Host)
        and do not call ``wtw``: a new tab's zshrc may not have loaded the wrapper yet,
        and older wrappers treated ``__cmux_*`` as an implicit go target. ``cd`` is a
        builtin, so this works even  before PATH or wtw.zsh exist.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $ProjectPath)

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $quoted = ConvertTo-WtwPosixSingleQuotedLiteral -Value $fullPath
    return "clear; cd $quoted"
}

function Get-WtwCmuxAppleScriptFallbackSource {
    <#
    .SYNOPSIS
        osascript body for the cmux AppleScript fallback.
    .DESCRIPTION
        Searches every window (not only the front one). Creating a tab in the
        front window dumped snowmain1's init command into whatever project was
        focused (e.g. kulissa-landing). A miss opens a new window.
    #>
    [CmdletBinding()]
    param()

    return @'
on run argv
    set targetPath to item 1 of argv
    set targetName to item 2 of argv
    set initCommand to item 3 of argv
    set matchByNameOnly to false
    if (count of argv) ≥ 4 then
        set matchByNameOnly to ((item 4 of argv) is "name-only")
    end if
    set tabLabel to targetName
    if (count of argv) ≥ 5 then
        set tabLabel to item 5 of argv
    end if

    tell application "cmux"
        activate

        repeat with candidateWindow in windows
            repeat with workspaceTab in tabs of candidateWindow
                try
                    set tabName to (name of workspaceTab as text)
                    if tabName is targetName or tabName is tabLabel then
                        select tab workspaceTab
                        return "selected"
                    end if

                    if not matchByNameOnly then
                        repeat with workspaceTerminal in terminals of workspaceTab
                            try
                                if (working directory of workspaceTerminal as text) is targetPath then
                                    select tab workspaceTab
                                    return "selected"
                                end if
                            end try
                        end repeat
                    end if
                end try
            end repeat
        end repeat

        set createdWindow to new window
        delay 1.0
        set createdTab to tab 1 of createdWindow
        select tab createdTab
        delay 0.4
        set createdTerminal to focused terminal of createdTab
        input text (initCommand & return) to createdTerminal
        return "created"
    end tell
end run
'@
}

function Open-WtwCmuxAppleScriptWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName,
        [string] $InitCommand,
        [switch] $MatchByNameOnly
    )

    if (-not $IsMacOS) { return $false }
    if (-not (Get-Command osascript -ErrorAction SilentlyContinue)) { return $false }

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
    if (-not $InitCommand) {
        $InitCommand = Get-WtwCmuxLocalAppleScriptInitCommand -ProjectPath $fullPath
    }
    $matchMode = if ($MatchByNameOnly) { 'name-only' } else { 'name-or-cwd' }
    $tabLabel = Get-WtwCmuxTabLabel -PrettyName $PrettyName
    $script = Get-WtwCmuxAppleScriptFallbackSource
    $result = & osascript @('-e', $script, '--', $fullPath, $PrettyName, $InitCommand, $matchMode, $tabLabel) 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Verbose "cmux AppleScript fallback failed: $($result -join [Environment]::NewLine)"
        return $false
    }

    return $true
}

function Open-WtwCmuxWorkspace {
    <#
    .SYNOPSIS
        Open a wtw target as a cmux workspace.
    .DESCRIPTION
        Selects an existing live cmux workspace for the target path/name when
        possible. Otherwise creates a new cmux workspace with the target cwd,
        name, and color. Falls back to `cmux <path>` when socket-driven creation
        is unavailable, which also launches cmux when needed.
    .PARAMETER Target
        Resolved wtw target object (output of Resolve-WtwTarget).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Target
    )

    if (-not (Test-WtwCmuxPresent)) {
        Write-Error "cmux is not installed or not on PATH. Install cmux or symlink '/Applications/cmux.app/Contents/Resources/bin/cmux'."
        return
    }

    $metadata = Resolve-WtwTerminalWorkspaceMetadata -Target $Target
    if (-not ($metadata -and $metadata.Path -and (Test-Path $metadata.Path))) {
        Write-Error 'No directory found for cmux target.'
        return
    }

    $fullDir = $metadata.Path
    $prettyName = $metadata.PrettyName
    $color = $metadata.Color
    $statusValue = $metadata.StatusValue

    Register-WtwCmuxProject `
        -ProjectPath $fullDir `
        -PrettyName $prettyName `
        -Color $color `
        -RepoName $Target.RepoName `
        -TaskName $Target.TaskName | Out-Null

    $existing = Find-WtwCmuxWorkspace -ProjectPath $fullDir -PrettyName $prettyName
    if ($existing) {
        $workspaceRef = Get-WtwCmuxWorkspaceRef -Workspace $existing
        if ($workspaceRef) {
            $selectResult = Invoke-WtwCmuxCommand -ArgumentList @('select-workspace', '--workspace', "$workspaceRef")
            if ($selectResult.ExitCode -eq 0) {
                Set-WtwCmuxWorkspaceMetadata `
                    -WorkspaceRef "$workspaceRef" `
                    -PrettyName $prettyName `
                    -Color $color `
                    -StatusValue $statusValue `
                    -CurrentName (Get-WtwCmuxWorkspaceName -Workspace $existing) `
                    -CurrentColor (Get-WtwCmuxObjectValue -Object $existing -Names @('color', 'workspace.color', 'sidebar.color', 'sidebarState.color'))
                Write-Host "  cmux: selected workspace '$prettyName'" -ForegroundColor Green
                return
            }
        }
    }

    $cmuxArgs = @(
        'new-workspace',
        '--name', $prettyName,
        '--cwd', $fullDir,
        '--command', 'pwsh -NoLogo -NoExit -Command "Clear-Host; wtw __cmux_init_current"',
        '--focus', 'true'
    )
    if ($statusValue) {
        $cmuxArgs += @('--description', "wtw: $statusValue")
    }
    $createResult = Invoke-WtwCmuxCommand -ArgumentList $cmuxArgs
    if ($createResult.ExitCode -ne 0) {
        $appleScriptInit = Get-WtwCmuxLocalAppleScriptInitCommand -ProjectPath $fullDir
        if (Open-WtwCmuxAppleScriptWorkspace -ProjectPath $fullDir -PrettyName $prettyName -InitCommand $appleScriptInit) {
            if (Test-WtwCmuxSocketPermissionDenied -Output $createResult.Output) {
                Write-Host "  cmux: opened via AppleScript fallback (socket access denied)." -ForegroundColor Green
            } else {
                Write-Host "  cmux: opened via AppleScript fallback." -ForegroundColor Green
            }
            return
        }

        if (Open-WtwCmuxAppPath -ProjectPath $fullDir) {
            Write-Host "  Opening in cmux: $fullDir" -ForegroundColor Green
            return
        }

        Write-Error "cmux workspace create failed: $($createResult.Output)"
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
        $created = Find-WtwCmuxWorkspace -ProjectPath $fullDir -PrettyName $prettyName
        if ($created) {
            $workspaceRef = Get-WtwCmuxWorkspaceRef -Workspace $created
        }
    }

    Set-WtwCmuxWorkspaceMetadata -WorkspaceRef "$workspaceRef" -PrettyName $prettyName -Color $color -StatusValue $statusValue -CurrentName $prettyName -CurrentColor $null
    Write-Host "  Opening in cmux: $fullDir" -ForegroundColor Green
}
