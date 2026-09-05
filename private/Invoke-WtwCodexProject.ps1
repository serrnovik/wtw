function Get-WtwCodexHome {
    [CmdletBinding()]
    param()

    if ($env:CODEX_HOME) {
        return [System.IO.Path]::GetFullPath($env:CODEX_HOME)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $HOME '.codex'))
}

function Test-WtwCodexPresent {
    [CmdletBinding()]
    param(
        [string] $CodexHome = (Get-WtwCodexHome)
    )

    if ($CodexHome -and (Test-Path $CodexHome)) { return $true }
    if (Get-WtwCodexCliPath) { return $true }
    if ($IsMacOS -and ((Test-Path '/Applications/ChatGPT.app') -or (Test-Path '/Applications/Codex.app'))) { return $true }

    return $false
}

function Get-WtwCodexCliPath {
    [CmdletBinding()]
    param()

    # A shell alias/function named `codex` can point back to wtw. Restrict the
    # lookup to real executables so Start-Process never tries to launch the
    # alias source (for example, the literal string "wtw").
    $command = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) { return $command.Source }

    return $null
}

function Get-WtwCodexMacAppName {
    [CmdletBinding()]
    param()

    foreach ($appName in 'ChatGPT', 'Codex') {
        if (Test-Path "/Applications/$appName.app") { return $appName }
    }

    return $null
}

function Test-WtwCodexAppRunning {
    [CmdletBinding()]
    param()

    return [bool](Get-Process -Name 'ChatGPT', 'Codex' -ErrorAction SilentlyContinue)
}

function Start-WtwCodexApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath
    )

    # The standalone CLI can lag behind an app rename and still hard-code the
    # legacy /Applications/Codex.app path. On macOS, launch the installed app
    # bundle directly and prefer its current ChatGPT name.
    if ($IsMacOS) {
        $appName = Get-WtwCodexMacAppName
        if ($appName) {
            & open -a $appName $ProjectPath
            return $true
        }
    }

    $codexExe = Get-WtwCodexCliPath
    if ($codexExe) {
        Start-Process -FilePath $codexExe -ArgumentList @('app', $ProjectPath)
        return $true
    }

    return $false
}

function Stop-WtwCodexProcess {
    [CmdletBinding()]
    param([int] $TimeoutSeconds = 10)

    $procs = @(Get-Process -Name 'ChatGPT', 'Codex' -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return $true }

    foreach ($process in $procs) {
        try { $process.CloseMainWindow() | Out-Null } catch { }
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-WtwCodexAppRunning)) { return $true }
        Start-Sleep -Milliseconds 250
    }

    foreach ($process in @(Get-Process -Name 'ChatGPT', 'Codex' -ErrorAction SilentlyContinue)) {
        try { $process.Kill($true) } catch { try { $process.Kill() } catch { } }
    }

    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-WtwCodexAppRunning)) { return $true }
        Start-Sleep -Milliseconds 250
    }

    return -not (Test-WtwCodexAppRunning)
}

function Resolve-WtwCodexStateConflict {
    [CmdletBinding()]
    param([string] $OperationLabel = 'update Codex project metadata')

    if (-not (Test-WtwCodexAppRunning)) { return @{ proceed = $true; relaunch = $false } }

    Write-Host ''
    Write-Host '  ChatGPT is running — it overwrites project labels on exit.' -ForegroundColor Yellow
    Write-Host "  How should I $OperationLabel"'?' -ForegroundColor Yellow
    Write-Host '    [c] Close ChatGPT yourself, then write (I will wait, then relaunch)'
    Write-Host '    [k] Force-kill ChatGPT, write, relaunch'
    Write-Host '    [i] Ignore — write anyway (ChatGPT may overwrite it)'
    Write-Host '    [s] Skip — open without changing the sidebar label'

    $answer = (Read-Host '  Choice [c/k/i/s]').Trim().ToLowerInvariant()
    if (-not $answer) { $answer = 'c' }

    switch ($answer) {
        'c' {
            Write-Host '  Waiting for ChatGPT to close (Ctrl+C to abort)...' -ForegroundColor Cyan
            while (Test-WtwCodexAppRunning) { Start-Sleep -Milliseconds 500 }
            Write-Host '  ChatGPT closed.' -ForegroundColor Green
            return @{ proceed = $true; relaunch = $true }
        }
        'k' {
            Write-Host '  Force-closing ChatGPT...' -ForegroundColor Cyan
            if (-not (Stop-WtwCodexProcess)) {
                Write-Host '  Could not stop ChatGPT — skipping label update.' -ForegroundColor Red
                return @{ proceed = $false; relaunch = $false }
            }
            Write-Host '  ChatGPT stopped.' -ForegroundColor Green
            return @{ proceed = $true; relaunch = $true }
        }
        's' {
            Write-Host '  Skipped ChatGPT label update.' -ForegroundColor DarkGray
            return @{ proceed = $false; relaunch = $false }
        }
        default {
            Write-Host '  Writing anyway — quit ChatGPT before restarting if it does not stick.' -ForegroundColor Yellow
            return @{ proceed = $true; relaunch = $false }
        }
    }
}

function ConvertTo-WtwTomlQuotedKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Value
    )

    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

function Get-WtwCodexProjectHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $ProjectPath
    )

    return '[projects.{0}]' -f (ConvertTo-WtwTomlQuotedKey $ProjectPath)
}

function Set-WtwCodexProjectTrust {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [string] $ConfigPath = (Join-Path (Get-WtwCodexHome) 'config.toml')
    )

    $configDir = Split-Path $ConfigPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }

    $raw = if (Test-Path $ConfigPath) { Get-Content -Path $ConfigPath -Raw } else { '' }
    $header = Get-WtwCodexProjectHeader $ProjectPath
    $sectionPattern = "(?ms)^$([regex]::Escape($header))\s*(\r?\n)(.*?)(?=^\[|\z)"
    $trustLine = 'trust_level = "trusted"'

    $match = [regex]::Match($raw, $sectionPattern)
    if ($match.Success) {
        $section = $match.Groups[0].Value
        $lineBreak = $match.Groups[1].Value
        $body = $match.Groups[3].Value
        if ($body -match '(?m)^trust_level\s*=') {
            $newBody = [regex]::Replace($body, '(?m)^trust_level\s*=.*$', $trustLine, 1)
        } else {
            $newBody = $body.TrimEnd() + $lineBreak + $trustLine + $lineBreak
        }
        $newSection = $header + $lineBreak + $newBody
        $raw = $raw.Substring(0, $match.Index) + $newSection + $raw.Substring($match.Index + $section.Length)
    } else {
        $prefix = if ([string]::IsNullOrWhiteSpace($raw)) { '' } else { $raw.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine }
        $raw = $prefix + $header + [Environment]::NewLine + $trustLine + [Environment]::NewLine
    }

    Backup-WtwExternalConfig -System 'codex' -Path $ConfigPath | Out-Null
    Set-Content -Path $ConfigPath -Value $raw -Encoding utf8
}

function Remove-WtwCodexProjectTrust {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [string] $ConfigPath = (Join-Path (Get-WtwCodexHome) 'config.toml')
    )

    if (-not (Test-Path $ConfigPath)) { return }

    $raw = Get-Content -Path $ConfigPath -Raw
    $header = Get-WtwCodexProjectHeader $ProjectPath
    $sectionPattern = "(?ms)^$([regex]::Escape($header))\s*(\r?\n)(.*?)(?=^\[|\z)"
    $match = [regex]::Match($raw, $sectionPattern)
    if (-not $match.Success) { return }

    $section = $match.Groups[0].Value
    $lineBreak = $match.Groups[1].Value
    $body = $match.Groups[3].Value
    $body = [regex]::Replace($body, '(?m)^trust_level\s*=.*(?:\r?\n)?', '')

    if ([string]::IsNullOrWhiteSpace($body)) {
        $raw = $raw.Substring(0, $match.Index) + $raw.Substring($match.Index + $section.Length)
    } else {
        $newSection = $header + $lineBreak + $body.TrimEnd() + $lineBreak
        $raw = $raw.Substring(0, $match.Index) + $newSection + $raw.Substring($match.Index + $section.Length)
    }

    Backup-WtwExternalConfig -System 'codex' -Path $ConfigPath | Out-Null
    Set-Content -Path $ConfigPath -Value $raw.TrimEnd() -Encoding utf8
}

function Add-WtwCodexArrayValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSObject] $State,
        [Parameter(Mandatory)][string] $PropertyName,
        [Parameter(Mandatory)][string] $Value,
        [switch] $Prepend
    )

    $items = @()
    $existing = $State.PSObject.Properties[$PropertyName]
    if ($existing -and $null -ne $existing.Value) {
        $items = @($existing.Value) | Where-Object { $_ -and $_ -ne $Value }
    }

    $items = if ($Prepend) { @($Value) + $items } else { $items + @($Value) }
    $State | Add-Member -NotePropertyName $PropertyName -NotePropertyValue @($items) -Force
}

function Remove-WtwCodexArrayValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSObject] $State,
        [Parameter(Mandatory)][string] $PropertyName,
        [Parameter(Mandatory)][string] $Value
    )

    $existing = $State.PSObject.Properties[$PropertyName]
    if (-not $existing) { return }

    $items = @($existing.Value) | Where-Object { $_ -and $_ -ne $Value }
    $State | Add-Member -NotePropertyName $PropertyName -NotePropertyValue @($items) -Force
}

function Get-WtwCodexNormalizedPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    try {
        return [System.IO.Path]::GetFullPath($Path).TrimEnd([char]'/', [char]'\')
    } catch {
        return $Path.TrimEnd([char]'/', [char]'\')
    }
}

function Get-WtwCodexLocalProjectEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSObject] $State,
        [Parameter(Mandatory)][string] $ProjectPath
    )

    $projectsProp = $State.PSObject.Properties['local-projects']
    if (-not ($projectsProp -and $projectsProp.Value)) { return }

    $normalizedProjectPath = Get-WtwCodexNormalizedPath -Path $ProjectPath
    foreach ($entry in $projectsProp.Value.PSObject.Properties) {
        $rootsProp = $entry.Value.PSObject.Properties['rootPaths']
        $rootPaths = @(
            if ($rootsProp -and $rootsProp.Value) { $rootsProp.Value }
        )
        foreach ($rootPath in $rootPaths) {
            if (-not $rootPath) { continue }
            $normalizedRootPath = Get-WtwCodexNormalizedPath -Path ([string]$rootPath)
            if ($normalizedRootPath -eq $normalizedProjectPath) {
                Write-Output $entry
                break
            }
        }
    }
}

function Set-WtwCodexLocalProjectName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSObject] $State,
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName
    )

    $projectsProp = $State.PSObject.Properties['local-projects']
    $projects = if ($projectsProp -and $projectsProp.Value) { $projectsProp.Value } else { [PSCustomObject]@{} }
    # No `@(...)[0]`: indexing an empty array throws under the module's
    # Set-StrictMode -Version Latest, and "no entry yet" is the normal case for a
    # freshly created worktree — which is exactly when this runs. `Select-Object
    # -First 1` already yields one object or nothing.
    $entry = Get-WtwCodexLocalProjectEntries -State $State -ProjectPath $ProjectPath | Select-Object -First 1
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

    if ($entry) {
        $project = $entry.Value
        $project | Add-Member -NotePropertyName 'id' -NotePropertyValue ([string]$entry.Name) -Force
        $project | Add-Member -NotePropertyName 'name' -NotePropertyValue $PrettyName -Force
        $project | Add-Member -NotePropertyName 'updatedAt' -NotePropertyValue $now -Force
        return [string]$entry.Name
    }

    $projectId = [guid]::NewGuid().ToString()
    $project = [PSCustomObject]@{
        id        = $projectId
        name      = $PrettyName
        rootPaths = @($ProjectPath)
        createdAt = $now
        updatedAt = $now
    }
    $projects | Add-Member -NotePropertyName $projectId -NotePropertyValue $project -Force
    $State | Add-Member -NotePropertyName 'local-projects' -NotePropertyValue $projects -Force
    return $projectId
}

function Set-WtwCodexProjectLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName,
        [string] $GlobalStatePath = (Join-Path (Get-WtwCodexHome) '.codex-global-state.json')
    )

    $stateDir = Split-Path $GlobalStatePath -Parent
    if (-not (Test-Path $stateDir)) {
        New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
    }

    if (Test-Path $GlobalStatePath) {
        try {
            $state = Get-Content -Path $GlobalStatePath -Raw | ConvertFrom-Json
        } catch {
            Write-Host "  ChatGPT: could not parse desktop state — skipping sidebar label update." -ForegroundColor Yellow
            return $false
        }
    } else {
        $state = [PSCustomObject]@{}
    }

    Add-WtwCodexArrayValue -State $state -PropertyName 'electron-saved-workspace-roots' -Value $ProjectPath -Prepend

    # Current ChatGPT Desktop renders the UUID-keyed local-projects model.
    # Keep the old root/label fields for backward compatibility, but make the
    # modern local-project record authoritative and remove its legacy path
    # duplicate from project-order.
    $localProjectId = Set-WtwCodexLocalProjectName -State $state -ProjectPath $ProjectPath -PrettyName $PrettyName
    Add-WtwCodexArrayValue -State $state -PropertyName 'project-order' -Value $localProjectId -Prepend
    Remove-WtwCodexArrayValue -State $state -PropertyName 'project-order' -Value $ProjectPath

    $labelsProp = $state.PSObject.Properties['electron-workspace-root-labels']
    $labels = if ($labelsProp -and $labelsProp.Value) { $labelsProp.Value } else { [PSCustomObject]@{} }
    $labels | Add-Member -NotePropertyName $ProjectPath -NotePropertyValue $PrettyName -Force
    $state | Add-Member -NotePropertyName 'electron-workspace-root-labels' -NotePropertyValue $labels -Force

    try {
        Backup-WtwExternalConfig -System 'codex' -Path $GlobalStatePath | Out-Null
        $state | ConvertTo-Json -Depth 80 -Compress | Set-Content -Path $GlobalStatePath -Encoding utf8
        return $true
    } catch {
        Write-Host "  ChatGPT: could not save desktop state — skipping sidebar label update." -ForegroundColor Yellow
        return $false
    }
}

function Get-WtwCodexProjectLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [string] $GlobalStatePath = (Join-Path (Get-WtwCodexHome) '.codex-global-state.json')
    )

    if (-not (Test-Path $GlobalStatePath)) { return $null }

    try {
        $state = Get-Content -Path $GlobalStatePath -Raw | ConvertFrom-Json
    } catch {
        return $null
    }

    # See Set-WtwCodexLocalProjectName: an unindexed pipeline, because @()[0]
    # throws under StrictMode when the project is not registered yet.
    $project = Get-WtwCodexLocalProjectEntries -State $state -ProjectPath $ProjectPath | Select-Object -First 1
    if ($project) { return [string]$project.Value.name }

    $labelsProp = $state.PSObject.Properties['electron-workspace-root-labels']
    if (-not ($labelsProp -and $labelsProp.Value)) { return $null }

    $labelProp = $labelsProp.Value.PSObject.Properties[$ProjectPath]
    if ($labelProp) { return [string]$labelProp.Value }

    $trimmedPath = $ProjectPath.TrimEnd([char]'/', [char]'\')
    if ($trimmedPath -ne $ProjectPath) {
        $labelProp = $labelsProp.Value.PSObject.Properties[$trimmedPath]
        if ($labelProp) { return [string]$labelProp.Value }
    }

    return $null
}

function Test-WtwCodexProjectLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName,
        [string] $GlobalStatePath = (Join-Path (Get-WtwCodexHome) '.codex-global-state.json')
    )

    $label = Get-WtwCodexProjectLabel -ProjectPath $ProjectPath -GlobalStatePath $GlobalStatePath
    if ($label -ne $PrettyName) { return $false }

    try {
        $state = Get-Content -Path $GlobalStatePath -Raw | ConvertFrom-Json
    } catch {
        return $false
    }

    # Same as above: unregistered is the answer this is asked for, not an error.
    $project = Get-WtwCodexLocalProjectEntries -State $state -ProjectPath $ProjectPath | Select-Object -First 1
    return $project -and $project.Value.name -eq $PrettyName
}

function Remove-WtwCodexProjectLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [string] $GlobalStatePath = (Join-Path (Get-WtwCodexHome) '.codex-global-state.json')
    )

    if (-not (Test-Path $GlobalStatePath)) { return $false }

    try {
        $state = Get-Content -Path $GlobalStatePath -Raw | ConvertFrom-Json
    } catch {
        Write-Host "  ChatGPT: could not parse desktop state — skipping sidebar cleanup." -ForegroundColor Yellow
        return $false
    }

    Remove-WtwCodexArrayValue -State $state -PropertyName 'electron-saved-workspace-roots' -Value $ProjectPath
    Remove-WtwCodexArrayValue -State $state -PropertyName 'project-order' -Value $ProjectPath
    Remove-WtwCodexArrayValue -State $state -PropertyName 'active-workspace-roots' -Value $ProjectPath

    $normalizedProjectPath = Get-WtwCodexNormalizedPath -Path $ProjectPath
    foreach ($project in @(Get-WtwCodexLocalProjectEntries -State $state -ProjectPath $ProjectPath)) {
        $projectId = [string]$project.Name
        # Re-wrap the filter: Where-Object on the last remaining root emits
        # nothing ($null), and on a single leftover root emits a bare string.
        # `.Count` on either throws under Set-StrictMode -Version Latest — which
        # is `wtw del` of a normal one-root ChatGPT project.
        $remainingRoots = @(@($project.Value.rootPaths) | Where-Object {
            $_ -and (Get-WtwCodexNormalizedPath -Path ([string]$_)) -ne $normalizedProjectPath
        })
        if ($remainingRoots.Count -eq 0) {
            $state.'local-projects'.PSObject.Properties.Remove($projectId)
            Remove-WtwCodexArrayValue -State $state -PropertyName 'project-order' -Value $projectId
        } else {
            $project.Value | Add-Member -NotePropertyName 'rootPaths' -NotePropertyValue @($remainingRoots) -Force
        }
    }

    $labelsProp = $state.PSObject.Properties['electron-workspace-root-labels']
    if ($labelsProp -and $labelsProp.Value) {
        $labelsProp.Value.PSObject.Properties.Remove($ProjectPath)
    }

    try {
        Backup-WtwExternalConfig -System 'codex' -Path $GlobalStatePath | Out-Null
        $state | ConvertTo-Json -Depth 80 -Compress | Set-Content -Path $GlobalStatePath -Encoding utf8
        return $true
    } catch {
        Write-Host "  ChatGPT: could not save desktop state — skipping sidebar cleanup." -ForegroundColor Yellow
        return $false
    }
}

function Ensure-WtwCodexProjectConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath
    )

    $codexDir = Join-Path $ProjectPath '.codex'
    $configPath = Join-Path $codexDir 'config.toml'
    if (Test-Path $configPath) { return $false }

    if (-not (Test-Path $codexDir)) {
        New-Item -Path $codexDir -ItemType Directory -Force | Out-Null
    }

    $content = @(
        '[features]',
        'hooks = true',
        ''
    ) -join [Environment]::NewLine
    Set-Content -Path $configPath -Value $content -Encoding utf8
    return $true
}

function Register-WtwCodexProject {
    <#
    .SYNOPSIS
        Register a worktree as a ChatGPT Desktop workspace when ChatGPT is present.
    .DESCRIPTION
        Best-effort integration: creates a minimal project config only when
        missing, trusts the worktree path in ~/.codex/config.toml, and updates
        ChatGPT Desktop's known workspace roots/sidebar label if the desktop
        state file exists.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName
    )

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $codexHome = Get-WtwCodexHome
    if (-not (Test-WtwCodexPresent -CodexHome $codexHome)) {
        Write-Host '  ChatGPT: not installed/present — skipping project registration.' -ForegroundColor DarkGray
        return $null
    }

    $isAppRunning = Test-WtwCodexAppRunning
    $createdProjectConfig = Ensure-WtwCodexProjectConfig -ProjectPath $fullPath
    Set-WtwCodexProjectTrust -ProjectPath $fullPath -ConfigPath (Join-Path $codexHome 'config.toml')
    $labelUpdated = if ($isAppRunning) {
        $false
    } else {
        Set-WtwCodexProjectLabel -ProjectPath $fullPath -PrettyName $PrettyName -GlobalStatePath (Join-Path $codexHome '.codex-global-state.json')
    }

    Write-Host "  ChatGPT: trusted project $fullPath" -ForegroundColor Green
    if ($createdProjectConfig) {
        Write-Host '  ChatGPT: created .codex/config.toml' -ForegroundColor Green
    }
    if ($labelUpdated) {
        Write-Host "  ChatGPT: sidebar label '$PrettyName'" -ForegroundColor Green
    } elseif ($isAppRunning) {
        Write-Host "  ChatGPT: app is running; run 'wtw chatgpt' to close/relaunch and finalize sidebar label '$PrettyName'." -ForegroundColor DarkGray
    } else {
        Write-Host "  ChatGPT: run 'wtw chatgpt' from the worktree to open it in ChatGPT Desktop." -ForegroundColor DarkGray
    }

    return $fullPath
}

function Unregister-WtwCodexProject {
    <#
    .SYNOPSIS
        Remove a worktree from ChatGPT Desktop's local project metadata.
    .DESCRIPTION
        Best-effort cleanup for the trust entry and sidebar/root state. Safe to
        call when ChatGPT is absent or the project was never registered.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath
    )

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $codexHome = Get-WtwCodexHome
    if (-not (Test-WtwCodexPresent -CodexHome $codexHome)) { return }

    Remove-WtwCodexProjectTrust -ProjectPath $fullPath -ConfigPath (Join-Path $codexHome 'config.toml')
    $labelRemoved = Remove-WtwCodexProjectLabel -ProjectPath $fullPath -GlobalStatePath (Join-Path $codexHome '.codex-global-state.json')

    Write-Host "  ChatGPT: removed project metadata for $fullPath" -ForegroundColor Green
    if ($labelRemoved) {
        Write-Host '  ChatGPT: removed sidebar label/root entries.' -ForegroundColor Green
    }
}
