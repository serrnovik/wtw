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

        $match = [regex]::Match($trimmed, '^(?:\*\s*)?(?<ref>(workspace|[0-9a-f]{8})[:0-9a-f-]*)\s*(?<name>.*?)(?:\s+\[selected\])?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
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
                        type    = 'terminal'
                        name    = (Get-WtwCmuxTabLabel -PrettyName $PrettyName)
                        command = 'pwsh -NoLogo -NoExit -Command "Clear-Host; wtw __cmux_init_current"'
                        focus   = $true
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

    if (-not ((Get-WtwPropertyNames -Object $Config) -contains 'workspaceGroups') -or -not $Config.workspaceGroups) {
        $Config | Add-Member -NotePropertyName 'workspaceGroups' -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    if (-not ((Get-WtwPropertyNames -Object $Config.workspaceGroups) -contains 'byCwd') -or -not $Config.workspaceGroups.byCwd) {
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

    return Backup-WtwExternalConfig -System 'cmux' -Path $ConfigPath
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
        Write-WtwHost '  cmux: CLI not installed/present - skipping project registration.' -ForegroundColor DarkGray
        return $null
    }

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $resolvedConfigPath = Get-WtwCmuxConfigPath -ConfigPath $ConfigPath
    $rawConfig = if (Test-Path $resolvedConfigPath) { Get-Content -Path $resolvedConfigPath -Raw } else { $null }
    $config = Read-JsoncFile $resolvedConfigPath
    if (-not $config) {
        $config = New-WtwCmuxConfig
    }
    if (-not ((Get-WtwPropertyNames -Object $config) -contains 'commands') -or -not $config.commands) {
        $config | Add-Member -NotePropertyName 'commands' -NotePropertyValue @() -Force
    }

    $before = ConvertTo-WtwCmuxConfigJson -Config $config
    $entry = New-WtwCmuxWorkspaceCommand -ProjectPath $fullPath -PrettyName $PrettyName -Color $Color -RepoName $RepoName -TaskName $TaskName
    $commandKey = $entry.id
    Set-WtwCmuxWorkspaceGroup -Config $config -ProjectPath $fullPath -Color $Color

    $commands = @($config.commands) | Where-Object {
        $id = if ((Get-WtwPropertyNames -Object $_) -contains 'id') { $_.id } else { $null }
        $name = if ((Get-WtwPropertyNames -Object $_) -contains 'name') { $_.name } else { $null }
        $cwd = if ((Get-WtwPropertyNames -Object $_) -contains 'workspace' -and $_.workspace -and (Get-WtwPropertyNames -Object $_.workspace) -contains 'cwd') {
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
        Write-WtwHost "  cmux: registered Command Palette workspace '$($entry.name)'" -ForegroundColor Green
        if ($rawConfig -match '(?m)^\s*//|/\*') {
            Write-WtwHost '  cmux: rewrote cmux.json as JSON; original with comments was backed up.' -ForegroundColor DarkGray
        }
    } else {
        Write-WtwHost "  cmux: Command Palette workspace already registered '$($entry.name)'" -ForegroundColor DarkGray
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
    if (-not ($config -and (Get-WtwPropertyNames -Object $config) -contains 'commands')) { return }

    $fullPath = if ($ProjectPath) { [System.IO.Path]::GetFullPath($ProjectPath) } else { $null }
    if (-not $CommandKey -and $fullPath) {
        $CommandKey = ConvertTo-WtwCmuxCommandKey -ProjectPath $fullPath
    }

    $before = ConvertTo-WtwCmuxConfigJson -Config $config
    $config.commands = @($config.commands) | Where-Object {
        $id = if ((Get-WtwPropertyNames -Object $_) -contains 'id') { $_.id } else { $null }
        $cwd = if ((Get-WtwPropertyNames -Object $_) -contains 'workspace' -and $_.workspace -and (Get-WtwPropertyNames -Object $_.workspace) -contains 'cwd') {
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
        Write-WtwHost '  cmux: removed Command Palette workspace metadata.' -ForegroundColor Green
        if ($rawConfig -match '(?m)^\s*//|/\*') {
            Write-WtwHost '  cmux: rewrote cmux.json as JSON; original with comments was backed up.' -ForegroundColor DarkGray
        }
    }
}

function ConvertTo-WtwCmuxRemoteCommandKey {
    <#
    .SYNOPSIS
        Stable cmux Command Palette id for a remote host (never hashed from HOME).
    .DESCRIPTION
        Local projects key off the worktree path. Remote machine projects all
        share the local home directory as cwd, so a path hash would collide
        and ``Unregister-WtwCmuxProject`` would wipe every remote entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $HostName
    )

    $safe = ($HostName.ToLowerInvariant() -replace '[^a-z0-9._-]', '-')
    return "wtw.remote.$safe"
}

function New-WtwCmuxRemoteWorkspaceCommand {
    <#
    .SYNOPSIS
        Command Palette entry whose surface SSHs into a configured wtw host.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [string] $HostSelector
    )

    if (-not $HostSelector) { $HostSelector = [string]$HostEntry.Name }
    $session = Resolve-WtwCmuxRemoteSession -HostEntry $HostEntry -HostSelector $HostSelector
    $localCwd = if ($HOME -and (Test-Path $HOME)) {
        [System.IO.Path]::GetFullPath($HOME)
    } else {
        [System.IO.Path]::GetFullPath((Get-Location).Path)
    }

    $keywords = [System.Collections.Generic.List[string]]::new()
    foreach ($word in @('wtw', 'remote', [string]$HostEntry.Name, [string]$HostEntry.Platform)) {
        if ($word) { [void]$keywords.Add($word) }
    }
    foreach ($alias in @($HostEntry.Aliases)) {
        if ($alias) { [void]$keywords.Add([string]$alias) }
    }

    $workspace = [PSCustomObject]@{
        name        = $session.PrettyName
        cwd         = $localCwd
        restart     = 'ignore'
        description = $session.StatusValue
        layout      = [PSCustomObject]@{
            pane = [PSCustomObject]@{
                surfaces = @(
                    [PSCustomObject]@{
                        type    = 'terminal'
                        name    = (Get-WtwCmuxTabLabel -PrettyName $session.PrettyName)
                        command = $session.Command
                        focus   = $true
                    }
                )
            }
        }
    }
    if ($session.Color) {
        $workspace | Add-Member -NotePropertyName 'color' -NotePropertyValue $session.Color -Force
    }

    $platform = if ($HostEntry.Platform) { [string]$HostEntry.Platform } else { 'remote' }
    return [PSCustomObject]@{
        id          = (ConvertTo-WtwCmuxRemoteCommandKey -HostName $HostEntry.Name)
        name        = "wtw remote: $($HostEntry.Name)"
        description = "SSH into $($HostEntry.Name) ($platform)"
        keywords    = @($keywords)
        workspace   = $workspace
    }
}

function Register-WtwCmuxRemoteProject {
    <#
    .SYNOPSIS
        Register a remote host as a cmux Command Palette / sidebar project.
    .DESCRIPTION
        Same persistence as a local worktree: picking the project in cmux starts
        ``wtw --on <host> go`` in a local tab. Keyed by host name, not cwd.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [string] $HostSelector,
        [string] $ConfigPath,
        [switch] $Quiet
    )

    if (-not (Test-WtwCmuxPresent)) {
        if (-not $Quiet) {
            Write-WtwHost '  cmux: CLI not installed/present - skipping remote project registration.' -ForegroundColor DarkGray
        }
        return $null
    }

    if (-not $HostSelector) { $HostSelector = [string]$HostEntry.Name }
    $resolvedConfigPath = Get-WtwCmuxConfigPath -ConfigPath $ConfigPath
    $rawConfig = if (Test-Path $resolvedConfigPath) { Get-Content -Path $resolvedConfigPath -Raw } else { $null }
    $config = Read-JsoncFile $resolvedConfigPath
    if (-not $config) {
        $config = New-WtwCmuxConfig
    }
    if (-not ((Get-WtwPropertyNames -Object $config) -contains 'commands') -or -not $config.commands) {
        $config | Add-Member -NotePropertyName 'commands' -NotePropertyValue @() -Force
    }

    $before = ConvertTo-WtwCmuxConfigJson -Config $config
    $entry = New-WtwCmuxRemoteWorkspaceCommand -HostEntry $HostEntry -HostSelector $HostSelector
    $commandKey = $entry.id

    $commands = @($config.commands) | Where-Object {
        $id = if ((Get-WtwPropertyNames -Object $_) -contains 'id') { $_.id } else { $null }
        $name = if ((Get-WtwPropertyNames -Object $_) -contains 'name') { $_.name } else { $null }
        $id -ne $commandKey -and $name -ne $entry.name
    }
    $config.commands = @($commands) + @($entry)

    $after = ConvertTo-WtwCmuxConfigJson -Config $config
    if ($before -ne $after) {
        Backup-WtwCmuxConfig -ConfigPath $resolvedConfigPath | Out-Null
        Save-WtwCmuxConfig -Config $config -ConfigPath $resolvedConfigPath
        if (-not $Quiet) {
            Write-WtwHost "  cmux: registered remote project '$($entry.name)'" -ForegroundColor Green
            if ($rawConfig -match '(?m)^\s*//|/\*') {
                Write-WtwHost '  cmux: rewrote cmux.json as JSON; original with comments was backed up.' -ForegroundColor DarkGray
            }
        }
    } elseif (-not $Quiet) {
        Write-WtwHost "  cmux: remote project already registered '$($entry.name)'" -ForegroundColor DarkGray
    }

    return $commandKey
}

function Unregister-WtwCmuxRemoteProject {
    <#
    .SYNOPSIS
        Remove the cmux Command Palette project for one remote host.
    .DESCRIPTION
        Matches only the ``wtw.remote.*`` id / ``wtw remote: <name>`` title.
        Never keys off cwd — remotes share the local home directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $HostName,
        [string] $ConfigPath
    )

    if (-not (Test-WtwCmuxPresent)) { return }

    $resolvedConfigPath = Get-WtwCmuxConfigPath -ConfigPath $ConfigPath
    if (-not (Test-Path $resolvedConfigPath)) { return }

    $rawConfig = Get-Content -Path $resolvedConfigPath -Raw
    $config = Read-JsoncFile $resolvedConfigPath
    if (-not ($config -and (Get-WtwPropertyNames -Object $config) -contains 'commands')) { return }

    $commandKey = ConvertTo-WtwCmuxRemoteCommandKey -HostName $HostName
    $paletteName = "wtw remote: $HostName"

    $before = ConvertTo-WtwCmuxConfigJson -Config $config
    $config.commands = @($config.commands) | Where-Object {
        $id = if ((Get-WtwPropertyNames -Object $_) -contains 'id') { $_.id } else { $null }
        $name = if ((Get-WtwPropertyNames -Object $_) -contains 'name') { $_.name } else { $null }
        $id -ne $commandKey -and $name -ne $paletteName
    }
    $after = ConvertTo-WtwCmuxConfigJson -Config $config

    if ($before -ne $after) {
        Backup-WtwCmuxConfig -ConfigPath $resolvedConfigPath | Out-Null
        Save-WtwCmuxConfig -Config $config -ConfigPath $resolvedConfigPath
        Write-WtwHost "  cmux: removed remote project '$paletteName'." -ForegroundColor Green
        if ($rawConfig -match '(?m)^\s*//|/\*') {
            Write-WtwHost '  cmux: rewrote cmux.json as JSON; original with comments was backed up.' -ForegroundColor DarkGray
        }
    }
}

function Sync-WtwCmuxRemoteProjects {
    <#
    .SYNOPSIS
        Register a cmux project for every configured wtw host.
    #>
    [CmdletBinding()]
    param(
        [string] $ConfigPath,
        [switch] $Quiet
    )

    if (-not (Test-WtwCmuxPresent)) { return }

    foreach ($hostEntry in @(Get-WtwHosts)) {
        Register-WtwCmuxRemoteProject -HostEntry $hostEntry -ConfigPath $ConfigPath -Quiet:$Quiet | Out-Null
    }
}
