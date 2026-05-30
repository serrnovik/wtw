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
        if ($parsed.PSObject.Properties.Name -contains 'workspaces') { return @($parsed.workspaces) }
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
    $workspaces = Get-WtwCmuxLiveWorkspaces
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
        Invoke-WtwCmuxCommand -ArgumentList @('set-status', 'wtw', $StatusValue, '--workspace', $WorkspaceRef, '--icon', 'git-branch', '--color', ($Color ?? '#7A4FD8'), '--priority', '90') | Out-Null
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

function Open-WtwCmuxAppleScriptWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName
    )

    if (-not $IsMacOS) { return $false }
    if (-not (Get-Command osascript -ErrorAction SilentlyContinue)) { return $false }

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $initCommand = "Clear-Host; Set-Location -LiteralPath $(ConvertTo-WtwPowerShellSingleQuotedLiteral -Value $fullPath); wtw __cmux_init_current"
    $script = @'
on run argv
    set targetPath to item 1 of argv
    set targetName to item 2 of argv
    set initCommand to item 3 of argv

    tell application "cmux"
        activate
        if (count of windows) is 0 then
            set targetWindow to new window
        else
            set targetWindow to front window
        end if

        repeat with workspaceTab in tabs of targetWindow
            try
                if (name of workspaceTab as text) is targetName then
                    select tab workspaceTab
                    return "selected"
                end if

                repeat with workspaceTerminal in terminals of workspaceTab
                    try
                        if (working directory of workspaceTerminal as text) is targetPath then
                            select tab workspaceTab
                            return "selected"
                        end if
                    end try
                end repeat
            end try
        end repeat

        set createdTab to new tab in targetWindow
        select tab createdTab
        delay 0.4
        set createdTerminal to focused terminal of createdTab
        input text (initCommand & return) to createdTerminal
        return "created"
    end tell
end run
'@

    $result = & osascript @('-e', $script, '--', $fullPath, $PrettyName, $initCommand) 2>&1
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

    $dir = if ($Target.WorktreeEntry) { $Target.WorktreeEntry.path } else { $Target.RepoEntry.mainPath }
    if (-not ($dir -and (Test-Path $dir))) {
        Write-Error 'No directory found for cmux target.'
        return
    }

    $fullDir = [System.IO.Path]::GetFullPath($dir)
    $prettyName = if ($Target.WorktreeEntry -and $Target.WorktreeEntry.PSObject.Properties.Name -contains 'prettyName' -and $Target.WorktreeEntry.prettyName) {
        $Target.WorktreeEntry.prettyName
    } elseif ($Target.TaskName) {
        $Target.TaskName
    } else {
        Split-Path $fullDir -Leaf
    }
    $color = if ($Target.WorktreeEntry -and $Target.WorktreeEntry.PSObject.Properties.Name -contains 'color') { $Target.WorktreeEntry.color } else { $null }
    $statusValue = if ($Target.TaskName) { "$($Target.RepoName)/$($Target.TaskName)" } else { $Target.RepoName }

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
        if (Open-WtwCmuxAppleScriptWorkspace -ProjectPath $fullDir -PrettyName $prettyName) {
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
