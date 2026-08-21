function Read-WtwJsonFile {
    <#
    .SYNOPSIS
        Read a JSON file, returning $null instead of throwing.
    .DESCRIPTION
        Used by best-effort local caches, where a missing, truncated, or
        concurrently rewritten file must behave exactly like "no data yet".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }
}

function ConvertTo-WtwUtcDate {
    <#
    .SYNOPSIS
        Parse a round-trip ("O") timestamp into UTC, returning $null when the
        value is missing or malformed.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value
    )

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $parsed = [DateTime]::MinValue
    $parsedOk = [DateTime]::TryParse(
        $text,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AdjustToUniversal,
        [ref] $parsed
    )
    if (-not $parsedOk -or $parsed -eq [DateTime]::MinValue) {
        return $null
    }

    return $parsed.ToUniversalTime()
}

function Get-WtwShellSessionKey {
    <#
    .SYNOPSIS
        Identify the shell session a wtw command was launched from.
    .DESCRIPTION
        The zsh/bash integration runs a fresh pwsh per command, so $PID changes
        on every invocation and cannot mark "already told this session". Those
        wrappers export WTW_SHELL_SESSION with the calling shell's PID, which is
        stable for the life of that terminal. In PowerShell, wtw runs in-process
        and $PID already identifies the session.
    #>
    [CmdletBinding()]
    param()

    $shellSession = [string]$env:WTW_SHELL_SESSION
    if (-not [string]::IsNullOrWhiteSpace($shellSession)) {
        return "shell-$($shellSession.Trim())"
    }

    return "pwsh-$PID"
}

function Save-WtwUpdateNoticeState {
    <#
    .SYNOPSIS
        Persist the local update-notice bookkeeping file.
    .DESCRIPTION
        Holds the last background-refresh timestamp and the shell sessions that
        have already seen a notice. Sessions older than the retention window are
        dropped so the file cannot grow without bound. Writing is best effort: a
        read-only or full HOME must not break a wtw command.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [AllowNull()]
        [object] $State,

        [DateTime] $LastRefreshSpawnUtc = [DateTime]::MinValue,

        [string] $NotifiedSession,

        [string] $NotifiedVersion,

        [TimeSpan] $SessionRetention = [TimeSpan]::FromDays(7),

        [int] $MaxSessions = 100
    )

    try {
        $now = [DateTime]::UtcNow

        $lastSpawn = if ($LastRefreshSpawnUtc -ne [DateTime]::MinValue) {
            $LastRefreshSpawnUtc
        } else {
            ConvertTo-WtwUtcDate -Value (Get-WtwPropertyValue -Object $State -Name 'LastRefreshSpawnUtc')
        }

        $sessions = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in @(Get-WtwPropertyValue -Object $State -Name 'NotifiedSessions' -DefaultValue @())) {
            if ($null -eq $entry) { continue }
            $session = [string](Get-WtwPropertyValue -Object $entry -Name 'Session' -DefaultValue '')
            if ([string]::IsNullOrWhiteSpace($session)) { continue }
            if (-not [string]::IsNullOrWhiteSpace($NotifiedSession) -and $session -eq $NotifiedSession) { continue }
            $at = ConvertTo-WtwUtcDate -Value (Get-WtwPropertyValue -Object $entry -Name 'AtUtc')
            if ($null -eq $at -or ($now - $at) -ge $SessionRetention) { continue }
            $sessions.Add([ordered]@{
                Session = $session
                Version = [string](Get-WtwPropertyValue -Object $entry -Name 'Version' -DefaultValue '')
                AtUtc   = $at.ToString('O')
            })
        }

        if (-not [string]::IsNullOrWhiteSpace($NotifiedSession)) {
            $sessions.Add([ordered]@{
                Session = $NotifiedSession
                Version = $NotifiedVersion
                AtUtc   = $now.ToString('O')
            })
        }

        if ($sessions.Count -gt $MaxSessions) {
            $sessions = [System.Collections.Generic.List[object]](@($sessions | Select-Object -Last $MaxSessions))
        }

        $directory = Split-Path -Parent $Path
        New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
        [ordered]@{
            LastRefreshSpawnUtc = if ($null -ne $lastSpawn) { $lastSpawn.ToString('O') } else { $null }
            NotifiedSessions    = @($sessions)
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Path -Encoding utf8 -ErrorAction Stop
    } catch {
        # Bookkeeping is optional; at worst the notice repeats.
    }
}

function Start-WtwUpdateCheck {
    <#
    .SYNOPSIS
        Refresh the Gallery version cache in a detached background process.
    .DESCRIPTION
        The foreground command never waits on the network. When the cache is
        stale this starts an independent pwsh that writes the cache and exits;
        the result is used by the next wtw command. A cooldown stamp keeps rapid
        successive commands from starting more than one refresh.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $CachePath,

        [Parameter(Mandatory)]
        [string] $StatePath,

        [TimeSpan] $Cooldown = [TimeSpan]::FromMinutes(10)
    )

    try {
        $manifestPath = Join-Path $script:WtwModuleRoot 'wtw.psd1'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            return
        }

        $pwshPath = [Environment]::ProcessPath
        if ([string]::IsNullOrWhiteSpace($pwshPath) -or -not (Test-Path -LiteralPath $pwshPath -PathType Leaf)) {
            return
        }

        $now = [DateTime]::UtcNow
        $state = Read-WtwJsonFile -Path $StatePath
        $lastSpawn = ConvertTo-WtwUtcDate -Value (Get-WtwPropertyValue -Object $state -Name 'LastRefreshSpawnUtc')
        if ($null -ne $lastSpawn -and ($now - $lastSpawn) -lt $Cooldown) {
            return
        }

        Save-WtwUpdateNoticeState -Path $StatePath -State $state -LastRefreshSpawnUtc $now

        $escapedManifest = $manifestPath.Replace("'", "''")
        $escapedCache = $CachePath.Replace("'", "''")
        $command = "Import-Module '$escapedManifest' -DisableNameChecking; " +
            "Get-WtwUpdateStatus -Force -CachePath '$escapedCache' | Out-Null"

        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $pwshPath
        foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command', $command)) {
            $startInfo.ArgumentList.Add($argument)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        # The child prints nothing; capturing its streams keeps any unexpected
        # output off the user's terminal instead of interleaving with wtw.
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        [Diagnostics.Process]::Start($startInfo) | Out-Null
    } catch {
        # A background update check is optional; never surface its failures.
    }
}

function Write-WtwUpdateNotice {
    <#
    .SYNOPSIS
        Print a short "a newer wtw is available" hint, at most once per shell
        session.
    .DESCRIPTION
        Reads only the locally cached PowerShell Gallery result, so it never
        waits on the network. When that cache is stale it starts a detached
        background refresh and prints nothing on this run; the next command uses
        the fresh result. Every failure mode - no cache, no network, an
        unreadable state file, a read-only HOME - is silent.

        The hint is skipped when output is redirected, which covers both CI and
        the wtw subcommands whose stdout the shell wrappers parse (go, __resolve,
        __aliases), and when WTW_NO_UPDATE_NOTICE is set.
    #>
    [CmdletBinding()]
    param(
        [string] $CachePath = (Join-Path $HOME '.wtw/update-check.json'),

        [string] $StatePath = (Join-Path $HOME '.wtw/update-notice.json'),

        [TimeSpan] $CacheTtl = [TimeSpan]::FromHours(24),

        [switch] $Force
    )

    try {
        if (-not $Force) {
            $optOut = [string]$env:WTW_NO_UPDATE_NOTICE
            if (-not [string]::IsNullOrWhiteSpace($optOut) -and $optOut -notin @('0', 'false', 'no')) {
                return
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$env:CI)) {
                return
            }
            if ([Console]::IsOutputRedirected) {
                return
            }
        }

        $manifestPath = Join-Path $script:WtwModuleRoot 'wtw.psd1'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            return
        }
        $currentVersion = $null
        $currentText = [string](Import-PowerShellDataFile -LiteralPath $manifestPath).ModuleVersion
        if (-not [version]::TryParse($currentText, [ref] $currentVersion)) {
            return
        }

        $cacheFile = [IO.Path]::GetFullPath($CachePath)
        $stateFile = [IO.Path]::GetFullPath($StatePath)
        $cache = Read-WtwJsonFile -Path $cacheFile
        $checkedAt = ConvertTo-WtwUtcDate -Value (Get-WtwPropertyValue -Object $cache -Name 'CheckedAtUtc')

        if ($null -eq $checkedAt -or ([DateTime]::UtcNow - $checkedAt) -ge $CacheTtl) {
            Start-WtwUpdateCheck -CachePath $cacheFile -StatePath $stateFile
            return
        }

        if ([string](Get-WtwPropertyValue -Object $cache -Name 'Status' -DefaultValue '') -ne 'Available') {
            return
        }
        $latestVersion = $null
        $latestText = [string](Get-WtwPropertyValue -Object $cache -Name 'LatestVersion' -DefaultValue '')
        if (-not [version]::TryParse($latestText, [ref] $latestVersion)) {
            return
        }
        if ($latestVersion -le $currentVersion) {
            return
        }

        $sessionKey = Get-WtwShellSessionKey
        $state = Read-WtwJsonFile -Path $stateFile
        foreach ($entry in @(Get-WtwPropertyValue -Object $state -Name 'NotifiedSessions' -DefaultValue @())) {
            if ($null -eq $entry) { continue }
            if ([string](Get-WtwPropertyValue -Object $entry -Name 'Session' -DefaultValue '') -ne $sessionKey) { continue }
            if ([string](Get-WtwPropertyValue -Object $entry -Name 'Version' -DefaultValue '') -eq $latestVersion.ToString()) {
                return
            }
        }

        Save-WtwUpdateNoticeState -Path $stateFile -State $state `
            -NotifiedSession $sessionKey -NotifiedVersion $latestVersion.ToString()

        # The update command depends on how this copy was installed. Telling a
        # hand-installed copy to run `Update-Module wtw` either errors outright or
        # updates a copy the shell never loads. Gallery copies are skipped here
        # deliberately — enumerating PSModulePath is too slow for a notice that
        # runs on every command.
        # Guarded: the notice is the point, the tailored command is the garnish.
        # An install probe that fails must not swallow "a new version exists".
        $install = try { Get-WtwInstallInfo } catch { $null }

        Write-Host ''
        Write-Host ("  wtw {0} is available (you have {1})." -f $latestVersion, $currentVersion) -ForegroundColor Cyan
        if ($install -and $install.Flavour -eq 'Repo') {
            Write-Host ("  You are running from a checkout at {0}" -f $install.ModuleRoot) -ForegroundColor DarkGray
            Write-Host '  Update: git pull, then wtw install' -ForegroundColor DarkGray
        } else {
            Write-Host '  Update: wtw update' -ForegroundColor DarkGray
        }
    } catch {
        # An update hint must never slow down, interrupt, or fail a wtw command.
    }
}
