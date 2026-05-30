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
        'workingDirectory',
        'currentWorkingDirectory',
        'sidebar.cwd',
        'sidebarState.cwd'
    )
}

function Get-WtwCmuxLiveWorkspaces {
    [CmdletBinding()]
    param()

    $result = Invoke-WtwCmuxCommand -ArgumentList @('list-workspaces')
    if ($result.ExitCode -ne 0) { return @() }

    $parsed = ConvertFrom-WtwCmuxJsonOutput -Output $result.Output
    if ($parsed) {
        if ($parsed -is [array]) { return @($parsed) }
        if ($parsed.PSObject.Properties.Name -contains 'workspaces') { return @($parsed.workspaces) }
        return @($parsed)
    }

    return ConvertFrom-WtwCmuxWorkspaceListOutput -Output $result.Output
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

    $cmuxArgs = @('new-workspace', '--name', $prettyName, '--cwd', $fullDir, '--focus', 'true')
    if ($statusValue) {
        $cmuxArgs += @('--description', "wtw: $statusValue")
    }
    $createResult = Invoke-WtwCmuxCommand -ArgumentList $cmuxArgs
    if ($createResult.ExitCode -ne 0) {
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
