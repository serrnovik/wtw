function Get-WtwWmuxBin {
    [CmdletBinding()]
    param()

    if ($env:WMUX_CLI -and (Test-Path $env:WMUX_CLI)) {
        return $env:WMUX_CLI
    }

    $cmd = Get-Command wmux -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    if (-not $IsWindows) { return $null }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs/wmux/wmux.exe'),
        (Join-Path $env:LOCALAPPDATA 'wmux/wmux.exe'),
        (Join-Path $env:ProgramFiles 'wmux/wmux.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'wmux/wmux.exe')
    ) | Where-Object { $_ }

    return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Test-WtwWmuxPresent {
    [CmdletBinding()]
    param()

    return [bool](Get-WtwWmuxBin)
}

function Invoke-WtwWmuxCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $ArgumentList
    )

    $wmux = Get-WtwWmuxBin
    if (-not $wmux) {
        return [PSCustomObject]@{ ExitCode = 127; Output = 'wmux CLI not found' }
    }

    Write-Verbose "wmux command: $wmux $($ArgumentList -join ' ')"
    $output = & $wmux @ArgumentList 2>&1
    $outputText = $output -join [Environment]::NewLine
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) {
        $exitCode = 1
        if ([string]::IsNullOrWhiteSpace($outputText)) {
            $outputText = 'wmux CLI command did not report an exit code.'
        }
    }

    if ($outputText -match 'failed to get single instance lock|gotLock\s*=\s*false') {
        $exitCode = 1
        if (-not ($outputText -match 'wmux CLI command was not accepted')) {
            $outputText = "wmux CLI command was not accepted by the running app. $outputText"
        }
    }

    return [PSCustomObject]@{ ExitCode = $exitCode; Output = $outputText }
}

function ConvertFrom-WtwWmuxJsonOutput {
    [CmdletBinding()]
    param([string] $Output)

    if ([string]::IsNullOrWhiteSpace($Output)) { return $null }
    try {
        return $Output | ConvertFrom-Json -Depth 100 -ErrorAction Stop
    } catch {
        return $null
    }
}

function Get-WtwWmuxObjectValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)][string[]] $Names
    )

    foreach ($name in $Names) {
        $prop = $Object.PSObject.Properties[$name]
        if ($prop -and $null -ne $prop.Value -and "$($prop.Value)" -ne '') {
            return $prop.Value
        }
    }

    return $null
}

function Get-WtwWmuxLiveWorkspaces {
    [CmdletBinding()]
    param()

    $result = Invoke-WtwWmuxCommand -ArgumentList @('list-workspaces', '--json')
    if ($result.ExitCode -ne 0) { return @() }

    $parsed = ConvertFrom-WtwWmuxJsonOutput -Output $result.Output
    if (-not $parsed) { return @() }
    if ($parsed -is [array]) { return @($parsed) }
    if ($parsed.PSObject.Properties.Name -contains 'workspaces') { return @($parsed.workspaces) }
    return @($parsed)
}

function Get-WtwWmuxLiveSurfaces {
    [CmdletBinding()]
    param()

    $result = Invoke-WtwWmuxCommand -ArgumentList @('list-surfaces', '--json')
    if ($result.ExitCode -ne 0) { return @() }

    $parsed = ConvertFrom-WtwWmuxJsonOutput -Output $result.Output
    if (-not $parsed) { return @() }
    if ($parsed -is [array]) { return @($parsed) }
    if ($parsed.PSObject.Properties.Name -contains 'surfaces') { return @($parsed.surfaces) }
    return @($parsed)
}

function Find-WtwWmuxWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $PrettyName)

    $workspaces = Get-WtwWmuxLiveWorkspaces
    if ($workspaces.Count -eq 0) { return $null }

    return $workspaces | Where-Object {
        $name = Get-WtwWmuxObjectValue -Object $_ -Names @('name', 'title', 'displayName')
        [string]::Equals($name, $PrettyName, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1
}

function ConvertTo-WtwWmuxPowerShellSingleQuotedLiteral {
    [CmdletBinding()]
    param([AllowNull()][string] $Value)

    return "'$($Value.Replace("'", "''"))'"
}

function Initialize-WtwWmuxWorkspaceShell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName
    )

    # Current wmux releases ignore cwd on new-workspace; newer builds may honor
    # --cwd on new-surface. Keep both paths useful by also sending Set-Location.
    $surfaceResult = Invoke-WtwWmuxCommand -ArgumentList @('new-surface', '--cwd', $ProjectPath)
    if ($surfaceResult.ExitCode -ne 0) {
        return [PSCustomObject]@{ Success = $false; Reason = "new-surface failed: $($surfaceResult.Output)" }
    }
    Start-Sleep -Milliseconds 250

    $initCommand = "Set-Location -LiteralPath $(ConvertTo-WtwWmuxPowerShellSingleQuotedLiteral -Value $ProjectPath); Clear-Host"
    $sendResult = Invoke-WtwWmuxCommand -ArgumentList @('send', $initCommand)
    if ($sendResult.ExitCode -ne 0) {
        return [PSCustomObject]@{ Success = $false; Reason = "send failed: $($sendResult.Output)" }
    }

    $enterResult = Invoke-WtwWmuxCommand -ArgumentList @('send-key', 'Enter')
    if ($enterResult.ExitCode -ne 0) {
        return [PSCustomObject]@{ Success = $false; Reason = "send-key failed: $($enterResult.Output)" }
    }

    return [PSCustomObject]@{ Success = $true; Reason = $null }
}

function Open-WtwWmuxProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName,
        [string] $StatusValue
    )

    if (-not $IsWindows) {
        return [PSCustomObject]@{ Success = $false; Reason = 'wmux is Windows-only' }
    }
    if (-not (Test-WtwWmuxPresent)) {
        return [PSCustomObject]@{ Success = $false; Reason = 'wmux CLI not found' }
    }

    return [PSCustomObject]@{
        Success = $false
        Created = $false
        WorkspaceName = $PrettyName
        Path = [System.IO.Path]::GetFullPath($ProjectPath)
        Reason = 'wmux CLI workspace/surface commands are no-op in the current installed wmux build; WTW integration is disabled until wmux exposes the substrate/API tracked in openwong2kim/wmux#15.'
    }
}

function Register-WtwWmuxProject {
    <#
    .SYNOPSIS
        Best-effort live wmux workspace registration for a worktree.
    .DESCRIPTION
        wmux currently exposes live workspace commands rather than a stable
        SourceGit-style on-disk repository registry. This therefore registers a
        worktree only when the wmux CLI is installed and reachable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName,
        [string] $RepoName,
        [string] $TaskName
    )

    if (-not $IsWindows) { return $null }
    if (-not (Test-WtwWmuxPresent)) { return $null }

    $statusValue = if ($RepoName -and $TaskName) { "$RepoName/$TaskName" } elseif ($RepoName) { $RepoName } else { $null }
    Write-Host '  wmux: integration pending upstream workspace/surface API - skipping project registration.' -ForegroundColor DarkGray
    return $null
}

function Unregister-WtwWmuxProject {
    [CmdletBinding()]
    param([string] $PrettyName)

    if (-not $IsWindows) { return }
    if (-not $PrettyName) { return }
    if (-not (Test-WtwWmuxPresent)) { return }

    $workspace = Find-WtwWmuxWorkspace -PrettyName $PrettyName
    if (-not $workspace) { return }

    $workspaceId = Get-WtwWmuxObjectValue -Object $workspace -Names @('id', 'ref', 'workspaceId')
    if (-not $workspaceId) { return }

    $result = Invoke-WtwWmuxCommand -ArgumentList @('close-workspace', "$workspaceId")
    if ($result.ExitCode -eq 0) {
        Write-Host "  wmux: removed live workspace '$PrettyName'." -ForegroundColor Green
    }
}
