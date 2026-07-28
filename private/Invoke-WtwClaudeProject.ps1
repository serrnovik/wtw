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

        [string[]] $AppNameCandidates = @('Claude')
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
        # Route through LaunchServices (not `open -a`): the scheme handler is what
        # knows how to turn the URL into a new Claude Code session.
        & open $url
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
