function Get-WtwCmuxBin {
    [CmdletBinding()]
    param()

    $cmd = Get-Command cmux -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $macBin = '/Applications/cmux.app/Contents/Resources/bin/cmux'
    if ($IsMacOS -and (Test-Path $macBin)) { return $macBin }

    return $null
}

function Test-WtwCmuxPresent {
    [CmdletBinding()]
    param()

    return [bool](Get-WtwCmuxBin)
}

function Get-WtwCmuxConfigPath {
    [CmdletBinding()]
    param([string] $ConfigPath)

    if ($ConfigPath) {
        return [System.IO.Path]::GetFullPath($ConfigPath.Replace('~', $HOME))
    }

    return [System.IO.Path]::GetFullPath((Join-Path $HOME '.config/cmux/cmux.json'))
}

function Invoke-WtwCmuxCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $ArgumentList
    )

    $cmux = Get-WtwCmuxBin
    if (-not $cmux) {
        return [PSCustomObject]@{ ExitCode = 127; Output = 'cmux CLI not found' }
    }

    $output = & $cmux @ArgumentList 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join [Environment]::NewLine) }
}

function Open-WtwCmuxAppPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $ProjectPath)

    if ($IsMacOS -and (Test-Path '/Applications/cmux.app')) {
        & open -a cmux $ProjectPath
        return ($LASTEXITCODE -eq 0)
    }

    return $false
}

function ConvertFrom-WtwCmuxJsonOutput {
    [CmdletBinding()]
    param([string] $Output)

    if ([string]::IsNullOrWhiteSpace($Output)) { return $null }

    try {
        return $Output | ConvertFrom-Json
    } catch {
        return $null
    }
}

function ConvertFrom-WtwCmuxWorkspaceListOutput {
    [CmdletBinding()]
    param([string] $Output)

    if ([string]::IsNullOrWhiteSpace($Output)) { return @() }

    $items = @()
    foreach ($line in ($Output -split '\r?\n')) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('Error:', [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        $match = [regex]::Match($trimmed, '^(?<ref>(workspace|[0-9a-f]{8})[:0-9a-f-]*)\s*(?<name>.*)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) { continue }

        $items += [PSCustomObject]@{
            ref  = $match.Groups['ref'].Value
            name = $match.Groups['name'].Value.Trim()
        }
    }

    return @($items)
}

function ConvertFrom-WtwCmuxCurrentWorkspaceOutput {
    [CmdletBinding()]
    param([string] $Output)

    if ([string]::IsNullOrWhiteSpace($Output)) { return $null }

    $json = ConvertFrom-WtwCmuxJsonOutput -Output $Output
    if ($json) { return $json }

    $firstLine = ($Output -split '\r?\n' | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
    if (-not $firstLine -or $firstLine.StartsWith('Error:', [System.StringComparison]::OrdinalIgnoreCase)) { return $null }

    if ($firstLine -match '^(?<ref>\S+)') {
        return [PSCustomObject]@{ ref = $matches.ref }
    }

    return $null
}

function ConvertTo-WtwCmuxCommandKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectPath
    )

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($fullPath)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    $hex = -join ($hash | ForEach-Object { $_.ToString('x2') })
    return "wtw.$($hex.Substring(0, 16))"
}

function ConvertTo-WtwCmuxConfigJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][PSObject] $Config)

    return ($Config | ConvertTo-Json -Depth 80)
}

function New-WtwCmuxConfig {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        commands = @()
    }
}

function New-WtwCmuxWorkspaceCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName,
        [string] $Color,
        [string] $RepoName,
        [string] $TaskName
    )

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $commandKey = ConvertTo-WtwCmuxCommandKey -ProjectPath $fullPath
    $keywords = @('wtw')
    if ($RepoName) { $keywords += $RepoName }
    if ($TaskName) { $keywords += $TaskName }

    $workspace = [PSCustomObject]@{
        name    = $PrettyName
        cwd     = $fullPath
        restart = 'ignore'
        layout  = [PSCustomObject]@{
            pane = [PSCustomObject]@{
                surfaces = @(
                    [PSCustomObject]@{
                        type  = 'terminal'
                        name  = 'Shell'
                        focus = $true
                    }
                )
            }
        }
    }
    if ($Color) {
        $workspace | Add-Member -NotePropertyName 'color' -NotePropertyValue $Color -Force
    }

    return [PSCustomObject]@{
        id          = $commandKey
        name        = "wtw: $PrettyName"
        description = "Open $fullPath"
        keywords    = @($keywords)
        workspace   = $workspace
    }
}

function Set-WtwCmuxWorkspaceGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSObject] $Config,
        [Parameter(Mandatory)][string] $ProjectPath,
        [string] $Color
    )

    if (-not $Color) { return }

    if (-not ($Config.PSObject.Properties.Name -contains 'workspaceGroups') -or -not $Config.workspaceGroups) {
        $Config | Add-Member -NotePropertyName 'workspaceGroups' -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    if (-not ($Config.workspaceGroups.PSObject.Properties.Name -contains 'byCwd') -or -not $Config.workspaceGroups.byCwd) {
        $Config.workspaceGroups | Add-Member -NotePropertyName 'byCwd' -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $existing = $Config.workspaceGroups.byCwd.PSObject.Properties[$fullPath]
    $group = if ($existing -and $existing.Value) { $existing.Value } else { [PSCustomObject]@{} }
    $group | Add-Member -NotePropertyName 'color' -NotePropertyValue $Color -Force
    $Config.workspaceGroups.byCwd | Add-Member -NotePropertyName $fullPath -NotePropertyValue $group -Force
}

function Backup-WtwCmuxConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $ConfigPath)

    if (-not (Test-Path $ConfigPath)) { return $null }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$ConfigPath.$timestamp.bak"
    Copy-Item -Path $ConfigPath -Destination $backupPath -Force
    return $backupPath
}

function Save-WtwCmuxConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSObject] $Config,
        [Parameter(Mandatory)][string] $ConfigPath
    )

    $dir = Split-Path $ConfigPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    ConvertTo-WtwCmuxConfigJson -Config $Config | Set-Content -Path $ConfigPath -Encoding utf8
}

function Register-WtwCmuxProject {
    <#
    .SYNOPSIS
        Register a worktree as a cmux Command Palette workspace command.
    .DESCRIPTION
        Maintains a stable wtw-owned command entry in ~/.config/cmux/cmux.json.
        Live cmux workspace IDs are intentionally not persisted because they are
        runtime refs. The command key returned here is stable for the project path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName,
        [string] $Color,
        [string] $RepoName,
        [string] $TaskName,
        [string] $ConfigPath
    )

    if (-not (Test-WtwCmuxPresent)) {
        Write-Host '  cmux: CLI not installed/present - skipping project registration.' -ForegroundColor DarkGray
        return $null
    }

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $resolvedConfigPath = Get-WtwCmuxConfigPath -ConfigPath $ConfigPath
    $rawConfig = if (Test-Path $resolvedConfigPath) { Get-Content -Path $resolvedConfigPath -Raw } else { $null }
    $config = Read-JsoncFile $resolvedConfigPath
    if (-not $config) {
        $config = New-WtwCmuxConfig
    }
    if (-not ($config.PSObject.Properties.Name -contains 'commands') -or -not $config.commands) {
        $config | Add-Member -NotePropertyName 'commands' -NotePropertyValue @() -Force
    }

    $before = ConvertTo-WtwCmuxConfigJson -Config $config
    $entry = New-WtwCmuxWorkspaceCommand -ProjectPath $fullPath -PrettyName $PrettyName -Color $Color -RepoName $RepoName -TaskName $TaskName
    $commandKey = $entry.id
    Set-WtwCmuxWorkspaceGroup -Config $config -ProjectPath $fullPath -Color $Color

    $commands = @($config.commands) | Where-Object {
        $id = if ($_.PSObject.Properties.Name -contains 'id') { $_.id } else { $null }
        $name = if ($_.PSObject.Properties.Name -contains 'name') { $_.name } else { $null }
        $cwd = if ($_.PSObject.Properties.Name -contains 'workspace' -and $_.workspace -and $_.workspace.PSObject.Properties.Name -contains 'cwd') {
            $_.workspace.cwd
        } else {
            $null
        }
        $id -ne $commandKey -and $name -ne $entry.name -and $cwd -ne $fullPath
    }
    $config.commands = @($commands) + @($entry)

    $after = ConvertTo-WtwCmuxConfigJson -Config $config
    if ($before -ne $after) {
        Backup-WtwCmuxConfig -ConfigPath $resolvedConfigPath | Out-Null
        Save-WtwCmuxConfig -Config $config -ConfigPath $resolvedConfigPath
        Write-Host "  cmux: registered Command Palette workspace '$($entry.name)'" -ForegroundColor Green
        if ($rawConfig -match '(?m)^\s*//|/\*') {
            Write-Host '  cmux: rewrote cmux.json as JSON; original with comments was backed up.' -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  cmux: Command Palette workspace already registered '$($entry.name)'" -ForegroundColor DarkGray
    }

    return $commandKey
}

function Unregister-WtwCmuxProject {
    <#
    .SYNOPSIS
        Remove a wtw-owned cmux Command Palette workspace command.
    #>
    [CmdletBinding()]
    param(
        [string] $ProjectPath,
        [string] $CommandKey,
        [string] $ConfigPath
    )

    if (-not (Test-WtwCmuxPresent)) { return }

    $resolvedConfigPath = Get-WtwCmuxConfigPath -ConfigPath $ConfigPath
    if (-not (Test-Path $resolvedConfigPath)) { return }

    $rawConfig = Get-Content -Path $resolvedConfigPath -Raw
    $config = Read-JsoncFile $resolvedConfigPath
    if (-not ($config -and $config.PSObject.Properties.Name -contains 'commands')) { return }

    $fullPath = if ($ProjectPath) { [System.IO.Path]::GetFullPath($ProjectPath) } else { $null }
    if (-not $CommandKey -and $fullPath) {
        $CommandKey = ConvertTo-WtwCmuxCommandKey -ProjectPath $fullPath
    }

    $before = ConvertTo-WtwCmuxConfigJson -Config $config
    $config.commands = @($config.commands) | Where-Object {
        $id = if ($_.PSObject.Properties.Name -contains 'id') { $_.id } else { $null }
        $cwd = if ($_.PSObject.Properties.Name -contains 'workspace' -and $_.workspace -and $_.workspace.PSObject.Properties.Name -contains 'cwd') {
            $_.workspace.cwd
        } else {
            $null
        }
        (-not $CommandKey -or $id -ne $CommandKey) -and (-not $fullPath -or $cwd -ne $fullPath)
    }
    $after = ConvertTo-WtwCmuxConfigJson -Config $config

    if ($before -ne $after) {
        Backup-WtwCmuxConfig -ConfigPath $resolvedConfigPath | Out-Null
        Save-WtwCmuxConfig -Config $config -ConfigPath $resolvedConfigPath
        Write-Host '  cmux: removed Command Palette workspace metadata.' -ForegroundColor Green
        if ($rawConfig -match '(?m)^\s*//|/\*') {
            Write-Host '  cmux: rewrote cmux.json as JSON; original with comments was backed up.' -ForegroundColor DarkGray
        }
    }
}
