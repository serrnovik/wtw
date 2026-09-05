# T3 Code integration.
#
# T3 Code 0.0.33 (alpha) ships no CLI and registers no `open-file`/`open-url`
# handler — its `second-instance` hook only reveals the existing window, and the
# `t3code://` scheme is the internal Electron renderer origin, not a routable
# deep link. So there is no supported way to tell a running T3 Code "open this
# folder".
#
# What it does have is an event-sourced store at ~/.t3/userdata/state.sqlite.
# Projects are `project.created` / `project.meta-updated` events on a `project`
# stream; `projection_projects` is a derived read model that the server replays
# forward from the checkpoint in `projection_state`. Appending one well-formed
# event is therefore enough — T3 materializes the project itself on next start,
# and wtw never has to touch a projection table.
#
# Project schema has `title` (the sidebar name) and `faviconPath` (an image), but
# no color field of any kind, so `wtw color` has nothing to drive here.

function Get-WtwT3BaseDir {
    <#
    .SYNOPSIS
        T3 Code's per-user base directory (`~/.t3` on every platform).
    #>
    [CmdletBinding()]
    param()

    return [System.IO.Path]::GetFullPath((Join-Path $HOME '.t3'))
}

function Get-WtwT3StatePath {
    <#
    .SYNOPSIS
        Path to T3 Code's event-store database. May not exist yet.
    #>
    [CmdletBinding()]
    param()

    return Join-Path (Join-Path (Get-WtwT3BaseDir) 'userdata') 'state.sqlite'
}

function Get-WtwT3SettingsPath {
    <#
    .SYNOPSIS
        Path to T3 Code's settings file. May not exist yet.
    #>
    [CmdletBinding()]
    param()

    return Join-Path (Join-Path (Get-WtwT3BaseDir) 'userdata') 'settings.json'
}

function Get-WtwT3ClientSettingsPath {
    <#
    .SYNOPSIS
        Path to T3 Code's renderer settings file. May not exist yet.
    #>
    [CmdletBinding()]
    param()

    return Join-Path (Join-Path (Get-WtwT3BaseDir) 'userdata') 'client-settings.json'
}

function Get-WtwT3EnvironmentId {
    <#
    .SYNOPSIS
        This machine's T3 environment id, or $null.
    .DESCRIPTION
        T3 addresses projects as `<environmentId>:<workspaceRoot>`, where the
        environment is the local install (remote environments are reachable only
        through the authenticated relay). wtw always works against this file, so
        it can never target another machine's projects by accident.
    #>
    [CmdletBinding()]
    param()

    $path = Join-Path (Join-Path (Get-WtwT3BaseDir) 'userdata') 'environment-id'
    if (-not (Test-Path $path)) { return $null }

    $id = (Get-Content -Path $path -Raw -ErrorAction SilentlyContinue)
    if (-not $id) { return $null }

    return $id.Trim()
}

function ConvertTo-WtwT3NormalizedPath {
    <#
    .SYNOPSIS
        Normalize a workspace root the way T3's renderer does.
    .DESCRIPTION
        Mirrors T3's `Dx()`: trim, strip trailing separators, and — for Windows
        drive-letter or UNC paths only — switch to backslashes and lowercase.
        POSIX paths are left case-sensitive. The key has to match byte for byte
        or the per-project override silently applies to nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $trimmed = $Path.Trim()
    if (-not $trimmed) { return $trimmed }

    # A bare root ('/', '\', 'C:\') is already normal — trimming it would empty it.
    if ($trimmed -in '/', '\' -or $trimmed -match '^[a-zA-Z]:[/\\]?$') { return $trimmed }

    $stripped = if ($trimmed.StartsWith('/')) {
        $trimmed -replace '/+$', ''
    } else {
        $trimmed -replace '[\\/]+$', ''
    }
    if (-not $stripped) { return $trimmed }

    $isWindowsPath = $stripped -match '^[a-zA-Z]:([/\\]|$)' -or $stripped.StartsWith('\\')
    if ($isWindowsPath) {
        return $stripped.Replace('/', '\').ToLowerInvariant()
    }

    return $stripped
}

function Get-WtwT3ProjectKey {
    <#
    .SYNOPSIS
        T3's `<environmentId>:<workspaceRoot>` key for a directory, or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkspaceRoot
    )

    $environmentId = Get-WtwT3EnvironmentId
    if (-not $environmentId) { return $null }

    $full = [System.IO.Path]::GetFullPath($WorkspaceRoot)
    return "${environmentId}:$(ConvertTo-WtwT3NormalizedPath -Path $full)"
}

function Test-WtwT3GroupingHidesTitles {
    <#
    .SYNOPSIS
        True when T3's sidebar will hide per-worktree project titles.
    .DESCRIPTION
        T3 groups sidebar projects by `sidebarProjectGroupingMode`, which defaults
        to "repository". That key is `repositoryIdentity.canonicalKey`, derived at
        runtime from the git remote — so every worktree of one repo lands in a
        single group, and the group renders its own label (the repository name)
        instead of the member projects' titles. A group only shows a project
        `title` when it has exactly one member.

        Under "separate" the key is the workspace root, so each worktree is its
        own single-member group and its wtw pretty name is what shows.

        wtw deliberately does not change this. Grouping sibling worktrees under
        one repository is T3's model — a worktree is the same project on another
        branch, and T3 already labels each thread with its branch. wtw only reads
        the effective mode (a per-project override beats the global setting) so it
        can word its own output honestly.
    #>
    [CmdletBinding()]
    param(
        [string] $WorkspaceRoot
    )

    $path = Get-WtwT3ClientSettingsPath
    if (-not (Test-Path $path)) { return $false }

    try {
        $settings = Get-Content -Path $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $false
    }

    if ($WorkspaceRoot) {
        $key = Get-WtwT3ProjectKey -WorkspaceRoot $WorkspaceRoot
        $overrides = Get-WtwPropertyValue -Object $settings -Name 'sidebarProjectGroupingOverrides'
        if ($key -and $overrides -and (Get-WtwPropertyNames -Object $overrides) -contains $key) {
            return (Get-WtwPropertyValue -Object $overrides -Name $key) -ne 'separate'
        }
    }

    $mode = Get-WtwPropertyValue -Object $settings -Name 'sidebarProjectGroupingMode' -DefaultValue 'repository'
    return $mode -ne 'separate'
}

function Get-WtwT3MacAppName {
    <#
    .SYNOPSIS
        First installed T3 Code app bundle name, or $null.
    .DESCRIPTION
        The alpha ships as "T3 Code (Alpha).app"; the candidate list lets the
        stable and beta bundle names work without a wtw release.
    #>
    [CmdletBinding()]
    param(
        [string[]] $Candidates = @('T3 Code', 'T3 Code (Alpha)', 'T3 Code (Beta)')
    )

    if (-not $IsMacOS) { return $null }

    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path "/Applications/$candidate.app")) { return $candidate }
    }

    return $null
}

function Test-WtwT3AppRunning {
    <#
    .SYNOPSIS
        True when T3 Code already has a process running.
    .DESCRIPTION
        Matched the same way as the Claude desktop app: pgrep misses the main
        Electron process on macOS, so compare the exact inner binary path from
        `ps` — helpers live under Contents/Frameworks/ and are excluded by
        anchoring the whole path.
    #>
    [CmdletBinding()]
    param(
        [string[]] $Candidates = @('T3 Code', 'T3 Code (Alpha)', 'T3 Code (Beta)')
    )

    if ($IsMacOS) {
        $processes = @(& ps -axo comm= 2>$null)
        foreach ($candidate in $Candidates) {
            if ($processes | Where-Object { $_ -eq "/Applications/$candidate.app/Contents/MacOS/$candidate" }) {
                return $true
            }
        }
        return $false
    }

    foreach ($candidate in $Candidates) {
        if (Get-Process -Name $candidate -ErrorAction SilentlyContinue) { return $true }
    }

    return $false
}

function Find-WtwT3WindowsExecutable {
    <#
    .SYNOPSIS
        Path to the winget-installed T3 Code executable, or $null.
    .DESCRIPTION
        `winget install T3Tools.T3Code` runs an electron-builder NSIS installer,
        which lands per-user under %LOCALAPPDATA%\Programs and adds no PATH entry
        — hence the explicit probe. The name candidates cover the alpha suffix the
        same way the macOS bundle lookup does.
    #>
    [CmdletBinding()]
    param()

    $roots = @()
    foreach ($base in @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        $roots += (Join-Path $base 'Programs')
        $roots += $base
    }

    foreach ($root in $roots) {
        foreach ($name in @('T3 Code (Alpha)', 'T3 Code (Beta)', 'T3 Code', 't3code')) {
            $candidate = Join-Path (Join-Path $root $name) "$name.exe"
            if (Test-Path $candidate) { return $candidate }
        }
    }

    return $null
}

function Stop-WtwT3Process {
    <#
    .SYNOPSIS
        Ask T3 Code to quit, escalating to a kill. $true once it is gone.
    .DESCRIPTION
        Tries a graceful window close first so the server checkpoints its WAL and
        shuts down cleanly, and only force-kills if that does not take.
    #>
    [CmdletBinding()]
    param(
        [string[]] $Candidates = @('T3 Code', 'T3 Code (Alpha)', 'T3 Code (Beta)'),

        [int] $TimeoutSeconds = 15
    )

    $procs = @(Get-Process -Name $Candidates -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0 -and -not (Test-WtwT3AppRunning -Candidates $Candidates)) { return $true }

    foreach ($process in $procs) {
        try { $process.CloseMainWindow() | Out-Null } catch { }
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-WtwT3AppRunning -Candidates $Candidates)) { return $true }
        Start-Sleep -Milliseconds 250
    }

    foreach ($process in @(Get-Process -Name $Candidates -ErrorAction SilentlyContinue)) {
        try { $process.Kill($true) } catch { try { $process.Kill() } catch { } }
    }

    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-WtwT3AppRunning -Candidates $Candidates)) { return $true }
        Start-Sleep -Milliseconds 250
    }

    return -not (Test-WtwT3AppRunning -Candidates $Candidates)
}

function Resolve-WtwT3StateConflict {
    <#
    .SYNOPSIS
        Decide what to do when T3 Code is running and holding its event store.
    .DESCRIPTION
        T3's server owns state.sqlite while it runs and tracks stream versions in
        memory, so an outside append can be lost or collide. Unlike the Codex
        equivalent there is deliberately no "write anyway" option — the failure
        mode is a corrupted stream rather than an overwritten label.

        Non-interactive sessions skip rather than block on a prompt.
    .OUTPUTS
        Hashtable with `proceed` and `relaunch`.
    #>
    [CmdletBinding()]
    param(
        [string[]] $Candidates = @('T3 Code', 'T3 Code (Alpha)', 'T3 Code (Beta)')
    )

    if (-not (Test-WtwT3AppRunning -Candidates $Candidates)) {
        return @{ proceed = $true; relaunch = $false }
    }

    if (-not [Environment]::UserInteractive) {
        return @{ proceed = $false; relaunch = $false }
    }

    Write-Host ''
    Write-Host '  T3 Code is running — it owns its project store while open.' -ForegroundColor Yellow
    Write-Host '  How should I register this worktree as a project?' -ForegroundColor Yellow
    Write-Host '    [c] Close T3 Code yourself, then register (I will wait, then relaunch)'
    Write-Host '    [k] Quit T3 Code for me, register, relaunch'
    Write-Host '    [s] Skip — just bring T3 Code forward'

    $answer = (Read-Host '  Choice [c/k/s]').Trim().ToLowerInvariant()
    if (-not $answer) { $answer = 'c' }

    switch ($answer) {
        'c' {
            Write-Host '  Waiting for T3 Code to close (Ctrl+C to abort)...' -ForegroundColor Cyan
            while (Test-WtwT3AppRunning -Candidates $Candidates) { Start-Sleep -Milliseconds 500 }
            Write-Host '  T3 Code closed.' -ForegroundColor Green
            return @{ proceed = $true; relaunch = $true }
        }
        'k' {
            Write-Host '  Closing T3 Code...' -ForegroundColor Cyan
            if (-not (Stop-WtwT3Process -Candidates $Candidates)) {
                Write-Host '  Could not stop T3 Code — skipping project registration.' -ForegroundColor Red
                return @{ proceed = $false; relaunch = $false }
            }
            Write-Host '  T3 Code stopped.' -ForegroundColor Green
            return @{ proceed = $true; relaunch = $true }
        }
        default {
            return @{ proceed = $false; relaunch = $false }
        }
    }
}

function Get-WtwSqliteCommand {
    <#
    .SYNOPSIS
        Path to a real sqlite3 executable, or $null.
    .DESCRIPTION
        -CommandType Application so a shell function or alias named sqlite3 is
        not mistaken for the binary. Ships with macOS; on Windows and most Linux
        distros it is a separate install, and every caller degrades to a no-op
        when it is missing.
    #>
    [CmdletBinding()]
    param()

    return (Get-Command sqlite3 -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1)?.Source
}

function ConvertTo-WtwSqlLiteral {
    <#
    .SYNOPSIS
        Quote a string as a SQL literal, escaping embedded single quotes.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Value
    )

    if ($null -eq $Value) { return 'NULL' }
    return "'" + $Value.Replace("'", "''") + "'"
}

function Invoke-WtwT3Query {
    <#
    .SYNOPSIS
        Query T3 Code's store. Returns @{ Ok; Rows; Error }.
    .DESCRIPTION
        Uses sqlite3's -json output so values survive the paths and emoji titles
        that would break the default pipe-delimited format.

        Deliberately NOT `-readonly`: T3's store is in WAL mode, and a read-only
        SQLite connection has to be able to create the `-shm` shared-memory file
        to read a WAL database. It cannot, so `-readonly` fails with "unable to
        open database file (14)" — intermittently while T3 is running, and again
        once it has quit leaving a hot WAL behind. A normal connection reads fine;
        the statements here are all SELECTs, so nothing is modified either way.

        Failure is reported rather than flattened into "no rows": callers must be
        able to tell "cannot read this store" from "this store has no such
        project", or they report the wrong reason to the user.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Sqlite,

        [Parameter(Mandatory)]
        [string] $DatabasePath,

        [Parameter(Mandatory)]
        [string] $Query
    )

    $failed = { param($message) [PSCustomObject]@{ Ok = $false; Rows = @(); Error = $message } }

    try {
        $raw = & $Sqlite -json $DatabasePath $Query 2>&1
    } catch {
        return & $failed $_.Exception.Message
    }

    if ($LASTEXITCODE -ne 0) {
        return & $failed (($raw -join ' ').Trim())
    }

    $text = ($raw -join "`n").Trim()
    if (-not $text) {
        return [PSCustomObject]@{ Ok = $true; Rows = @(); Error = $null }
    }

    try {
        return [PSCustomObject]@{ Ok = $true; Rows = @($text | ConvertFrom-Json -ErrorAction Stop); Error = $null }
    } catch {
        return & $failed "could not parse sqlite3 output: $($_.Exception.Message)"
    }
}

function Invoke-WtwT3Write {
    <#
    .SYNOPSIS
        Execute a SQL script against T3 Code's store. $true when it succeeded.
    .DESCRIPTION
        Piped in on stdin rather than passed as an argument so multi-statement
        scripts and embedded quoting survive the PowerShell → native boundary
        unchanged.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Sqlite,

        [Parameter(Mandatory)]
        [string] $DatabasePath,

        [Parameter(Mandatory)]
        [string] $Script
    )

    try {
        $Script | & $Sqlite $DatabasePath 2>&1 | Out-Null
    } catch {
        Write-Warning "T3 Code: could not write $DatabasePath — project not registered. ($($_.Exception.Message))"
        return $false
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "T3 Code: sqlite3 rejected the project event (exit $LASTEXITCODE) — project not registered."
        return $false
    }

    return $true
}

function Test-WtwT3StateSchema {
    <#
    .SYNOPSIS
        Check the store still matches the schema wtw appends to. Returns @{ Ok; Error }.
    .DESCRIPTION
        T3 Code is alpha, so its event schema can change under us. Verify the
        exact columns this integration writes before touching anything, and bail
        out rather than inserting a row a newer T3 cannot decode.

        An unreadable store is reported as its own failure, never as schema drift.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Sqlite,

        [Parameter(Mandatory)]
        [string] $DatabasePath
    )

    $required = @(
        'event_id', 'aggregate_kind', 'stream_id', 'stream_version', 'event_type',
        'occurred_at', 'command_id', 'causation_event_id', 'correlation_id',
        'actor_kind', 'payload_json', 'metadata_json'
    )

    $result = Invoke-WtwT3Query -Sqlite $Sqlite -DatabasePath $DatabasePath `
        -Query "SELECT name FROM pragma_table_info('orchestration_events')"
    if (-not $result.Ok) {
        return [PSCustomObject]@{ Ok = $false; Error = "could not read T3 Code's store — $($result.Error)" }
    }

    $columns = @($result.Rows | ForEach-Object { $_.name })
    if ($columns.Count -eq 0) {
        return [PSCustomObject]@{ Ok = $false; Error = "no orchestration_events table in T3 Code's store" }
    }

    $missing = @($required | Where-Object { $columns -notcontains $_ })
    if ($missing.Count -gt 0) {
        return [PSCustomObject]@{ Ok = $false; Error = "T3 Code's event schema changed (missing: $($missing -join ', ')) — skipping" }
    }

    # The read model wtw is relying on T3 to rebuild from the appended event.
    $projection = Invoke-WtwT3Query -Sqlite $Sqlite -DatabasePath $DatabasePath `
        -Query "SELECT 1 AS ok FROM sqlite_master WHERE type = 'table' AND name = 'projection_projects'"
    if (-not $projection.Ok) {
        return [PSCustomObject]@{ Ok = $false; Error = "could not read T3 Code's store — $($projection.Error)" }
    }
    if ($projection.Rows.Count -eq 0) {
        return [PSCustomObject]@{ Ok = $false; Error = "no projection_projects table in T3 Code's store — skipping" }
    }

    # The pending-event lookup reads payloads with json_extract (SQLite JSON1).
    # Without it wtw cannot tell an already-appended project from a new one and
    # would create duplicates, so treat a missing JSON1 as a hard stop.
    $json = Invoke-WtwT3Query -Sqlite $Sqlite -DatabasePath $DatabasePath `
        -Query "SELECT json_extract('{""a"":1}', '`$.a') AS a"
    if (-not $json.Ok) {
        return [PSCustomObject]@{ Ok = $false; Error = 'this sqlite3 has no JSON1 support — cannot register T3 projects safely' }
    }

    return [PSCustomObject]@{ Ok = $true; Error = $null }
}

function Get-WtwT3Project {
    <#
    .SYNOPSIS
        The live T3 Code project for a workspace root, or $null.
    .OUTPUTS
        PSCustomObject with ProjectId and Title.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Sqlite,

        [Parameter(Mandatory)]
        [string] $DatabasePath,

        [Parameter(Mandatory)]
        [string] $WorkspaceRoot
    )

    # Look in the event stream as well as the read model, not just the read model.
    # wtw appends events and lets T3 project them on next start, so between the
    # append and that restart `projection_projects` still has no row — and a
    # projection-only lookup would happily create the same project a second time.
    #
    # Title comes from the newest title-bearing event on the stream so a pending
    # rename is not re-issued either, falling back to the projected title when a
    # store has been compacted and the creating event is gone.
    $literal = ConvertTo-WtwSqlLiteral $WorkspaceRoot
    $result = Invoke-WtwT3Query -Sqlite $Sqlite -DatabasePath $DatabasePath -Query @"
WITH candidate AS (
  SELECT project_id, title, workspace_root
  FROM projection_projects
  WHERE deleted_at IS NULL
  UNION ALL
  SELECT e.stream_id,
         json_extract(e.payload_json, '`$.title'),
         json_extract(e.payload_json, '`$.workspaceRoot')
  FROM orchestration_events e
  WHERE e.aggregate_kind = 'project' AND e.event_type = 'project.created'
)
SELECT c.project_id AS projectId,
       COALESCE((
         SELECT json_extract(x.payload_json, '`$.title')
         FROM orchestration_events x
         WHERE x.aggregate_kind = 'project' AND x.stream_id = c.project_id
           AND json_extract(x.payload_json, '`$.title') IS NOT NULL
         ORDER BY x.stream_version DESC LIMIT 1
       ), c.title) AS title
FROM candidate c
WHERE c.workspace_root = $literal
  AND NOT EXISTS (
    SELECT 1 FROM orchestration_events d
    WHERE d.aggregate_kind = 'project' AND d.stream_id = c.project_id
      AND d.event_type = 'project.deleted'
  )
  AND NOT EXISTS (
    SELECT 1 FROM projection_projects p
    WHERE p.project_id = c.project_id AND p.deleted_at IS NOT NULL
  )
LIMIT 1
"@

    if (-not $result.Ok -or $result.Rows.Count -eq 0) { return $null }

    return [PSCustomObject]@{
        ProjectId = $result.Rows[0].projectId
        Title     = $result.Rows[0].title
    }
}

function New-WtwT3EventStatements {
    <#
    .SYNOPSIS
        SQL appending one project event plus its command receipt (no transaction).
    .DESCRIPTION
        stream_version is derived in SQL exactly the way T3's own event store
        derives it (last version on the stream + 1, or 0 for a new stream), so a
        concurrently-written event cannot leave a gap. The receipt row mirrors
        what T3 writes for its own commands; the projection is built from the
        event, so the receipt is bookkeeping only.

        The receipt's result_sequence looks the event up by event_id rather than
        using last_insert_rowid(): when several of these are chained, the previous
        statement is a receipt insert, so last_insert_rowid() would point at that
        receipt instead of the event.
    .PARAMETER EventType
        'project.created' or 'project.meta-updated'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('project.created', 'project.meta-updated')]
        [string] $EventType,

        [Parameter(Mandatory)]
        [string] $ProjectId,

        [Parameter(Mandatory)]
        [string] $Payload,

        [Parameter(Mandatory)]
        [string] $OccurredAt
    )

    $eventId   = [guid]::NewGuid().ToString()
    $commandId = [guid]::NewGuid().ToString()

    $eventLit   = ConvertTo-WtwSqlLiteral $eventId
    $commandLit = ConvertTo-WtwSqlLiteral $commandId
    $streamLit  = ConvertTo-WtwSqlLiteral $ProjectId
    $typeLit    = ConvertTo-WtwSqlLiteral $EventType
    $whenLit    = ConvertTo-WtwSqlLiteral $OccurredAt
    $payloadLit = ConvertTo-WtwSqlLiteral $Payload

    return @"
INSERT INTO orchestration_events (
  event_id, aggregate_kind, stream_id, stream_version, event_type, occurred_at,
  command_id, causation_event_id, correlation_id, actor_kind, payload_json, metadata_json
) VALUES (
  $eventLit, 'project', $streamLit,
  COALESCE((
    SELECT stream_version + 1 FROM orchestration_events
    WHERE aggregate_kind = 'project' AND stream_id = $streamLit
    ORDER BY stream_version DESC LIMIT 1
  ), 0),
  $typeLit, $whenLit, $commandLit, NULL, $commandLit, 'client', $payloadLit, '{}'
);
INSERT INTO orchestration_command_receipts (
  command_id, aggregate_kind, aggregate_id, accepted_at, result_sequence, status, error
) VALUES (
  $commandLit, 'project', $streamLit, $whenLit,
  (SELECT sequence FROM orchestration_events WHERE event_id = $eventLit),
  'accepted', NULL
);
"@
}

function New-WtwT3EventScript {
    <#
    .SYNOPSIS
        Wrap one or more event statement blocks in a single transaction.
    .DESCRIPTION
        Creating a project takes two events — `project.created`, then a
        `project.meta-updated` carrying the fields the created payload has no
        room for. One transaction keeps a half-registered project impossible.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Statements
    )

    return "BEGIN IMMEDIATE;`n" + ($Statements -join "`n") + "`nCOMMIT;"
}

function Get-WtwT3RegistrationPlan {
    <#
    .SYNOPSIS
        Work out what registering a worktree would do, without writing anything.
    .DESCRIPTION
        Every check here is a read, so it is safe (and accurate) while T3 Code is
        running. Splitting it out is what lets `wtw t3` stay quiet on an
        already-registered worktree instead of asking to quit T3 on every run.
    .OUTPUTS
        PSCustomObject with Action ('create' | 'rename' | 'none' | 'blocked'),
        Reason, Sqlite, DatabasePath, ProjectId and FullPath.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectPath,

        [Parameter(Mandatory)]
        [string] $PrettyName
    )

    $blocked = { param($reason) [PSCustomObject]@{ Action = 'blocked'; Reason = $reason } }

    $databasePath = Get-WtwT3StatePath
    if (-not (Test-Path $databasePath)) {
        return & $blocked 'T3 Code has no store yet — launch it once first.'
    }

    $sqlite = Get-WtwSqliteCommand
    if (-not $sqlite) {
        return & $blocked 'no sqlite3 on PATH — cannot register the project.'
    }

    $schema = Test-WtwT3StateSchema -Sqlite $sqlite -DatabasePath $databasePath
    if (-not $schema.Ok) {
        return & $blocked $schema.Error
    }

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $existing = Get-WtwT3Project -Sqlite $sqlite -DatabasePath $databasePath -WorkspaceRoot $fullPath

    $action = if (-not $existing) { 'create' } elseif ($existing.Title -ne $PrettyName) { 'rename' } else { 'none' }

    # Not `$existing?.ProjectId`: `?` is legal in a PowerShell variable name, so
    # that parses as the variable `$existing?` and silently yields $null.
    $projectId = if ($existing) { $existing.ProjectId } else { $null }

    return [PSCustomObject]@{
        Action       = $action
        Reason       = $null
        Sqlite       = $sqlite
        DatabasePath = $databasePath
        ProjectId    = $projectId
        FullPath     = $fullPath
    }
}

function Register-WtwT3Project {
    <#
    .SYNOPSIS
        Make a worktree show up in T3 Code's sidebar under its wtw pretty name.
    .DESCRIPTION
        Appends a `project.created` event when T3 has never seen the directory,
        or a `project.meta-updated` event when it has but under a different
        title. No-ops when the title already matches.

        Refuses to write while T3 Code is running: its server owns the database
        and tracks stream versions in memory, so an outside append during a live
        session can be lost or conflict. Nothing here is destructive — the worst
        case is an extra sidebar entry the user can delete in the UI.
    .PARAMETER ProjectPath
        Worktree directory to register as the project's workspace root.
    .PARAMETER PrettyName
        Sidebar title. T3 Code has no project color, so this is the whole of the
        per-worktree identity it can express.
    .OUTPUTS
        PSCustomObject with Status ('created' | 'renamed' | 'unchanged' | 'skipped')
        and Reason when skipped.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectPath,

        [Parameter(Mandatory)]
        [string] $PrettyName
    )

    $skipped = { param($reason) [PSCustomObject]@{ Status = 'skipped'; Reason = $reason } }

    if (Test-WtwT3AppRunning) {
        return & $skipped 'T3 Code is running — quit it first to register this worktree.'
    }

    $plan = Get-WtwT3RegistrationPlan -ProjectPath $ProjectPath -PrettyName $PrettyName
    if ($plan.Action -eq 'blocked') { return & $skipped $plan.Reason }
    if ($plan.Action -eq 'none')    { return [PSCustomObject]@{ Status = 'unchanged'; Reason = $null } }

    $sqlite       = $plan.Sqlite
    $databasePath = $plan.DatabasePath
    $fullPath     = $plan.FullPath
    $now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

    if ($plan.Action -eq 'rename') {
        $payload = [ordered]@{
            projectId = $plan.ProjectId
            title     = $PrettyName
            updatedAt = $now
        } | ConvertTo-Json -Compress -Depth 5

        $script = New-WtwT3EventScript -Statements @(
            New-WtwT3EventStatements -EventType 'project.meta-updated' `
                -ProjectId $plan.ProjectId -Payload $payload -OccurredAt $now
        )

        if (-not (Invoke-WtwT3Write -Sqlite $sqlite -DatabasePath $databasePath -Script $script)) {
            return & $skipped 'the rename event could not be written.'
        }

        return [PSCustomObject]@{ Status = 'renamed'; Reason = $null }
    }

    $projectId = [guid]::NewGuid().ToString()
    # defaultModelSelection is nullable in T3's payload schema; leaving it null
    # lets the app apply the user's configured default instead of pinning a model.
    $payload = [ordered]@{
        projectId             = $projectId
        title                 = $PrettyName
        workspaceRoot         = $fullPath
        defaultModelSelection = $null
        scripts               = @()
        createdAt             = $now
        updatedAt             = $now
    } | ConvertTo-Json -Compress -Depth 5

    # `defaultThreadEnvMode` has no slot in ProjectCreatedPayload, and Effect
    # Schema drops unknown keys, so pinning it takes a follow-up meta-update.
    # It matters: the worktree already exists, so new threads must run in this
    # checkout ("local"). Left unset, a global default of "worktree" would have
    # T3 cut a fresh git worktree *from* a wtw worktree for every thread.
    $envPayload = [ordered]@{
        projectId            = $projectId
        defaultThreadEnvMode = 'local'
        updatedAt            = $now
    } | ConvertTo-Json -Compress -Depth 5

    $script = New-WtwT3EventScript -Statements @(
        (New-WtwT3EventStatements -EventType 'project.created' `
            -ProjectId $projectId -Payload $payload -OccurredAt $now),
        (New-WtwT3EventStatements -EventType 'project.meta-updated' `
            -ProjectId $projectId -Payload $envPayload -OccurredAt $now)
    )

    if (-not (Invoke-WtwT3Write -Sqlite $sqlite -DatabasePath $databasePath -Script $script)) {
        return & $skipped 'the project event could not be written.'
    }

    return [PSCustomObject]@{ Status = 'created'; Reason = $null }
}

function Set-WtwT3AddProjectBaseDirectory {
    <#
    .SYNOPSIS
        Point T3 Code's "Add project starts in" picker at a directory.
    .DESCRIPTION
        A fallback for the cases Register-WtwT3Project has to skip (T3 running,
        no sqlite3): the Add Project browser opens here instead of `~/`, so the
        worktree is one click away. No-ops when the settings file is absent —
        wtw does not bootstrap T3 Code's config.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $settingsPath = Get-WtwT3SettingsPath
    if (-not (Test-Path $settingsPath)) { return $false }

    try {
        $settings = Get-Content -Path $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warning "T3 Code: could not read $settingsPath — leaving settings alone. ($($_.Exception.Message))"
        return $false
    }

    if (-not $settings) { $settings = [PSCustomObject]@{} }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ((Get-WtwPropertyValue -Object $settings -Name 'addProjectBaseDirectory') -eq $fullPath) {
        return $true
    }

    $settings | Add-Member -NotePropertyName 'addProjectBaseDirectory' -NotePropertyValue $fullPath -Force

    # -Depth 100: the default of 2 would flatten nested provider settings into
    # type names and corrupt the file.
    $temp = "$settingsPath.wtw-$PID.tmp"
    try {
        Backup-WtwExternalConfig -System 't3' -Path $settingsPath | Out-Null
        Set-Content -Path $temp -Value ($settings | ConvertTo-Json -Depth 100) -NoNewline -ErrorAction Stop
        Move-Item -Path $temp -Destination $settingsPath -Force -ErrorAction Stop
    } catch {
        Remove-Item -Path $temp -Force -ErrorAction SilentlyContinue
        Write-Warning "T3 Code: could not write $settingsPath — settings unchanged. ($($_.Exception.Message))"
        return $false
    }

    return $true
}
