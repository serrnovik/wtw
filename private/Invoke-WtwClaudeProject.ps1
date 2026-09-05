function Get-WtwClaudeMacAppName {
    <#
    .SYNOPSIS
        First installed Claude desktop app bundle name, or $null.
    #>
    [CmdletBinding()]
    param(
        [string[]] $Candidates = @('Claude')
    )

    if (-not $IsMacOS) { return $null }

    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path "/Applications/$candidate.app")) { return $candidate }
    }

    return $null
}

function Get-WtwClaudeCodeConfigPath {
    <#
    .SYNOPSIS
        Path to Claude Code's per-user config file (`~/.claude.json`).
    .DESCRIPTION
        Honours $env:CLAUDE_CONFIG_DIR, which relocates the whole Claude Code
        config directory. Returns the path whether or not the file exists —
        callers decide what to do when it is missing.
    #>
    [CmdletBinding()]
    param()

    $root = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { $HOME }
    return [System.IO.Path]::GetFullPath((Join-Path $root '.claude.json'))
}

function Set-WtwClaudeCodeProjectTrust {
    <#
    .SYNOPSIS
        Set or clear the "Trust this workspace?" answer for a directory.
    .DESCRIPTION
        Claude Code stores the trust decision in `~/.claude.json` under
        `projects.<abs-path>.hasTrustDialogAccepted`. Pre-seeding it means a
        freshly created worktree does not re-prompt the first time it is opened.

        That file is written live by every running Claude Code session, so this
        keeps the read/modify/write window as short as possible and swaps the
        file in via an atomic rename instead of truncating it in place. It is a
        no-op when the file does not exist — wtw does not bootstrap Claude Code's
        config, mirroring how the Superset/Codex/cmux registrations no-op when
        those tools are absent.
    .PARAMETER ProjectPath
        Directory to trust (or un-trust).
    .PARAMETER Remove
        Drop the whole `projects.<path>` entry instead of trusting it. Used by
        `wtw remove`, where the directory itself is going away.
    .OUTPUTS
        The normalized project path on success, otherwise $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectPath,

        [switch] $Remove
    )

    $configPath = Get-WtwClaudeCodeConfigPath
    if (-not (Test-Path $configPath)) { return $null }

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)

    try {
        $config = Get-Content -Path $configPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warning "Claude Code: could not read $configPath — skipping trust update. ($($_.Exception.Message))"
        return $null
    }

    if (-not $config) { return $null }

    $projects = Get-WtwPropertyValue -Object $config -Name 'projects'
    if ($Remove) {
        if (-not $projects) { return $null }
        if ((Get-WtwPropertyNames -Object $projects) -notcontains $fullPath) { return $null }
        $projects.PSObject.Properties.Remove($fullPath)
    } else {
        if (-not $projects) {
            $projects = [PSCustomObject]@{}
            $config | Add-Member -NotePropertyName 'projects' -NotePropertyValue $projects -Force
        }

        $entry = Get-WtwPropertyValue -Object $projects -Name $fullPath
        if (-not $entry) {
            $entry = [PSCustomObject]@{}
            $projects | Add-Member -NotePropertyName $fullPath -NotePropertyValue $entry -Force
        }

        if ((Get-WtwPropertyValue -Object $entry -Name 'hasTrustDialogAccepted') -eq $true) {
            return $fullPath   # already trusted — leave the file untouched
        }

        $entry | Add-Member -NotePropertyName 'hasTrustDialogAccepted' -NotePropertyValue $true -Force
    }

    # -Depth 100: the default of 2 would silently flatten nested project state
    # (history, MCP server config) into type names and corrupt the file.
    try {
        $json = $config | ConvertTo-Json -Depth 100
    } catch {
        Write-Warning "Claude Code: could not serialize $configPath — skipping trust update. ($($_.Exception.Message))"
        return $null
    }

    $temp = "$configPath.wtw-$PID.tmp"
    try {
        Backup-WtwExternalConfig -System 'claude' -Path $configPath | Out-Null
        Set-Content -Path $temp -Value $json -NoNewline -ErrorAction Stop
        Move-Item -Path $temp -Destination $configPath -Force -ErrorAction Stop
    } catch {
        Remove-Item -Path $temp -Force -ErrorAction SilentlyContinue
        Write-Warning "Claude Code: could not write $configPath — trust unchanged. ($($_.Exception.Message))"
        return $null
    }

    return $fullPath
}

function Register-WtwClaudeCodeProject {
    <#
    .SYNOPSIS
        Pre-accept Claude Code's workspace-trust prompt for a new worktree.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectPath
    )

    return Set-WtwClaudeCodeProjectTrust -ProjectPath $ProjectPath
}

function Unregister-WtwClaudeCodeProject {
    <#
    .SYNOPSIS
        Drop a removed worktree's Claude Code project state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectPath
    )

    return Set-WtwClaudeCodeProjectTrust -ProjectPath $ProjectPath -Remove
}

function Test-WtwClaudeAppRunning {
    <#
    .SYNOPSIS
        True when the Claude desktop app already has a process running.
    #>
    [CmdletBinding()]
    param(
        [string] $AppName = 'Claude'
    )

    if ($IsMacOS) {
        # pgrep does not see the main Electron process on macOS — `pgrep -x Claude`
        # and `pgrep -f <bundle path>` both miss it while still matching the
        # "Claude Helper" children. Match the exact inner binary in `ps` instead;
        # helpers live under Contents/Frameworks/, so anchoring the whole path
        # excludes them.
        $binary = "/Applications/$AppName.app/Contents/MacOS/$AppName"
        $processes = @(& ps -axo comm= 2>$null)
        return [bool] ($processes | Where-Object { $_ -eq $binary })
    }

    return [bool] (Get-Process -Name $AppName -ErrorAction SilentlyContinue)
}

function New-WtwClaudeCodeDeepLink {
    <#
    .SYNOPSIS
        Build a `claude://code/new` deep link for a project directory.
    .DESCRIPTION
        Claude for Desktop registers the `claude://` URL scheme. Its deep-link
        router accepts host `code` with path `/new`, and forwards exactly three
        query parameters to the new-session screen:

            folder  — absolute path the Claude Code session is rooted at (repeatable)
            q       — text pre-filled into the composer (also accepted as `prompt`)
            file    — read by the handler but currently dropped for `code/new`

        Anything else (a session title, a color) is discarded by the app, so this
        helper only emits folder/q. The app caps `q` at ~14k characters.
    .PARAMETER ProjectPath
        Directory the new Claude Code session should open in.
    .PARAMETER Prompt
        Optional text to pre-fill the composer with (not auto-submitted).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectPath,

        [string] $Prompt
    )

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $query = "folder=$([uri]::EscapeDataString($fullPath))"

    if ($Prompt) {
        $trimmed = if ($Prompt.Length -gt 14000) { $Prompt.Substring(0, 14000) } else { $Prompt }
        $query += "&q=$([uri]::EscapeDataString($trimmed))"
    }

    return "claude://code/new?$query"
}

function Start-WtwClaudeCodeSession {
    <#
    .SYNOPSIS
        Open a new Claude Code chat in the Claude desktop app, rooted at a directory.
    .DESCRIPTION
        Hands the `claude://code/new` deep link to the OS URL opener so the
        registered Claude desktop app handles it — launching the app first when
        it is not already running. Returns a result object rather than throwing so
        callers can print a wtw-styled message.
    .PARAMETER ProjectPath
        Directory the new Claude Code session should open in.
    .PARAMETER Prompt
        Optional text to pre-fill the composer with.
    .PARAMETER AppNameCandidates
        Ordered macOS app bundle names to accept (handles future renames).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectPath,

        [string] $Prompt,

        [string[]] $AppNameCandidates = @('Claude'),

        [int] $LaunchTimeoutSeconds = 20
    )

    $url = New-WtwClaudeCodeDeepLink -ProjectPath $ProjectPath -Prompt $Prompt

    if ($IsMacOS) {
        # Probe the bundle first so a missing install reports the app name instead
        # of macOS's opaque "no application knows how to open this URL".
        $appName = Get-WtwClaudeMacAppName -Candidates $AppNameCandidates
        if (-not $appName) {
            $tried = ($AppNameCandidates | ForEach-Object { "$_.app" }) -join ', '
            return [PSCustomObject]@{ Success = $false; Url = $url; Reason = "Claude for Desktop is not installed. Tried: $tried" }
        }

        # Cold start drops the link: the app's URL handler gives up when the main
        # webContents is not attached yet, and the app then boots to whatever
        # surface it last showed (usually Chat). Launch first, wait for the window,
        # and re-send once — `code/new` just navigates, so a repeat is harmless.
        $coldStart = -not (Test-WtwClaudeAppRunning -AppName $appName)
        if ($coldStart) {
            Write-Host '  Claude is not running — launching it first...' -ForegroundColor DarkGray
            & open -a $appName
            $deadline = (Get-Date).AddSeconds($LaunchTimeoutSeconds)
            while (-not (Test-WtwClaudeAppRunning -AppName $appName) -and (Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 250
            }
            Start-Sleep -Seconds 3
        }

        # Route through LaunchServices (not `open -a`): the scheme handler is what
        # knows how to turn the URL into a new Claude Code session.
        & open $url
        if ($coldStart) {
            Start-Sleep -Seconds 4
            & open $url
        }

        return [PSCustomObject]@{ Success = $true; Url = $url; Reason = $null }
    }

    if ($IsWindows) {
        try {
            Start-Process $url -ErrorAction Stop
            return [PSCustomObject]@{ Success = $true; Url = $url; Reason = $null }
        } catch {
            return [PSCustomObject]@{ Success = $false; Url = $url; Reason = "No handler registered for claude:// — install Claude for Desktop. ($($_.Exception.Message))" }
        }
    }

    $opener = Get-Command xdg-open -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $opener) {
        return [PSCustomObject]@{ Success = $false; Url = $url; Reason = 'No xdg-open on PATH to dispatch the claude:// deep link.' }
    }

    & $opener.Source $url
    return [PSCustomObject]@{ Success = $true; Url = $url; Reason = $null }
}
