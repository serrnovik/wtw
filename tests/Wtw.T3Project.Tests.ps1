BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
    Get-ChildItem -Path "$PSScriptRoot/../public" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }

    $script:Sqlite = (Get-Command sqlite3 -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1)?.Source

    # Minimal stand-in for T3 Code's store: the two tables wtw writes, plus the
    # projection it relies on T3 to rebuild from the appended event.
    function New-T3TestStore {
        param([string] $Path)

        @'
CREATE TABLE orchestration_events (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id TEXT NOT NULL UNIQUE,
  aggregate_kind TEXT NOT NULL,
  stream_id TEXT NOT NULL,
  stream_version INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  command_id TEXT,
  causation_event_id TEXT,
  correlation_id TEXT,
  actor_kind TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  metadata_json TEXT NOT NULL
);
CREATE UNIQUE INDEX idx_stream_version ON orchestration_events(aggregate_kind, stream_id, stream_version);
CREATE TABLE orchestration_command_receipts (
  command_id TEXT PRIMARY KEY,
  aggregate_kind TEXT NOT NULL,
  aggregate_id TEXT NOT NULL,
  accepted_at TEXT NOT NULL,
  result_sequence INTEGER NOT NULL,
  status TEXT NOT NULL,
  error TEXT
);
CREATE TABLE projection_projects (
  project_id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  workspace_root TEXT NOT NULL,
  scripts_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);
'@ | & $script:Sqlite $Path
    }
}

Describe 'T3 Code project registration' -Skip:(-not (Get-Command sqlite3 -CommandType Application -ErrorAction SilentlyContinue)) {
    BeforeEach {
        $script:StoreDir = Join-Path ([System.IO.Path]::GetTempPath()) "wtw-t3-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $script:StoreDir -Force | Out-Null
        $script:StorePath = Join-Path $script:StoreDir 'state.sqlite'
        New-T3TestStore -Path $script:StorePath

        $script:WorkPath = Join-Path $script:StoreDir 'repo_task'
        New-Item -ItemType Directory -Path $script:WorkPath -Force | Out-Null

        Mock Get-WtwT3StatePath { $script:StorePath }
        Mock Test-WtwT3AppRunning { $false }
    }

    AfterEach {
        Remove-Item -Path $script:StoreDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'appends a project.created event carrying the pretty name' {
        $result = Register-WtwT3Project -ProjectPath $script:WorkPath -PrettyName 'PF037 gamification'
        $result.Status | Should -Be 'created'

        $row = & $script:Sqlite -json $script:StorePath `
            "SELECT event_type, stream_version, actor_kind, payload_json FROM orchestration_events" |
            ConvertFrom-Json

        $row.event_type     | Should -Be 'project.created'
        $row.stream_version | Should -Be 0
        $row.actor_kind     | Should -Be 'client'

        $payload = $row.payload_json | ConvertFrom-Json
        $payload.title         | Should -Be 'PF037 gamification'
        $payload.workspaceRoot | Should -Be ([System.IO.Path]::GetFullPath($script:WorkPath))
        # Nullable in T3's schema — leaving it unset lets the app pick the user's default.
        $payload.defaultModelSelection | Should -BeNullOrEmpty
    }

    It 'writes a matching command receipt for the appended event' {
        Register-WtwT3Project -ProjectPath $script:WorkPath -PrettyName 'Alpha' | Out-Null

        $receipt = & $script:Sqlite -json $script:StorePath @'
SELECT r.status, r.aggregate_kind, r.result_sequence, e.sequence AS eventSequence
FROM orchestration_command_receipts r
JOIN orchestration_events e ON e.command_id = r.command_id
'@ | ConvertFrom-Json

        $receipt.status          | Should -Be 'accepted'
        $receipt.aggregate_kind  | Should -Be 'project'
        $receipt.result_sequence | Should -Be $receipt.eventSequence
    }

    It 'renames via project.meta-updated when the projection already has the directory' {
        $full = [System.IO.Path]::GetFullPath($script:WorkPath)
        & $script:Sqlite $script:StorePath @"
INSERT INTO projection_projects VALUES ('p1', 'repo_task', '$full', '[]', 'now', 'now', NULL);
"@

        $result = Register-WtwT3Project -ProjectPath $script:WorkPath -PrettyName 'Renamed'
        $result.Status | Should -Be 'renamed'

        $row = & $script:Sqlite -json $script:StorePath `
            "SELECT event_type, stream_id, payload_json FROM orchestration_events" | ConvertFrom-Json

        $row.event_type | Should -Be 'project.meta-updated'
        $row.stream_id  | Should -Be 'p1'
        ($row.payload_json | ConvertFrom-Json).title | Should -Be 'Renamed'
    }

    # wtw only appends events; T3 rebuilds projection_projects on its next start.
    # A lookup that consulted the projection alone would see nothing in between
    # and create the same project again on every `wtw t3`.
    It 'does not create a second project before T3 has projected the first' {
        (Register-WtwT3Project -ProjectPath $script:WorkPath -PrettyName 'Once').Status |
            Should -Be 'created'
        (Register-WtwT3Project -ProjectPath $script:WorkPath -PrettyName 'Once').Status |
            Should -Be 'unchanged'

        (& $script:Sqlite $script:StorePath 'SELECT COUNT(*) FROM orchestration_events') |
            Should -Be '1'
        (& $script:Sqlite $script:StorePath 'SELECT COUNT(*) FROM projection_projects') |
            Should -Be '0' -Because 'wtw must never write the read model itself'
    }

    It 'reads a pending rename back instead of re-issuing it' {
        Register-WtwT3Project -ProjectPath $script:WorkPath -PrettyName 'First'  | Out-Null
        (Register-WtwT3Project -ProjectPath $script:WorkPath -PrettyName 'Second').Status |
            Should -Be 'renamed'
        (Register-WtwT3Project -ProjectPath $script:WorkPath -PrettyName 'Second').Status |
            Should -Be 'unchanged'

        # sqlite3 -json prints the array across several lines; join before parsing.
        $events = ((& $script:Sqlite -json $script:StorePath `
            'SELECT event_type, stream_version FROM orchestration_events ORDER BY sequence') -join "`n") |
            ConvertFrom-Json
        $events.Count | Should -Be 2
        # Both events must land on the same stream, versions 0 then 1.
        $events[1].event_type     | Should -Be 'project.meta-updated'
        $events[1].stream_version | Should -Be 1
        (& $script:Sqlite $script:StorePath 'SELECT COUNT(DISTINCT stream_id) FROM orchestration_events') |
            Should -Be '1'
    }

    It 'writes nothing when the title already matches' {
        $full = [System.IO.Path]::GetFullPath($script:WorkPath)
        & $script:Sqlite $script:StorePath @"
INSERT INTO projection_projects VALUES ('p1', 'Same', '$full', '[]', 'now', 'now', NULL);
"@

        (Register-WtwT3Project -ProjectPath $script:WorkPath -PrettyName 'Same').Status |
            Should -Be 'unchanged'

        (& $script:Sqlite $script:StorePath 'SELECT COUNT(*) FROM orchestration_events') |
            Should -Be '0'
    }

    It 'ignores a soft-deleted project and creates a fresh one' {
        $full = [System.IO.Path]::GetFullPath($script:WorkPath)
        & $script:Sqlite $script:StorePath @"
INSERT INTO projection_projects VALUES ('p1', 'Gone', '$full', '[]', 'now', 'now', 'deleted');
"@

        (Register-WtwT3Project -ProjectPath $script:WorkPath -PrettyName 'Fresh').Status |
            Should -Be 'created'
    }

    It 'survives quotes and emoji in the pretty name' {
        $name = "it's 🛘 done"
        (Register-WtwT3Project -ProjectPath $script:WorkPath -PrettyName $name).Status |
            Should -Be 'created'

        $payload = (& $script:Sqlite -json $script:StorePath 'SELECT payload_json FROM orchestration_events' |
            ConvertFrom-Json).payload_json | ConvertFrom-Json
        $payload.title | Should -Be $name
    }

    It 'refuses to write while T3 Code is running' {
        Mock Test-WtwT3AppRunning { $true }

        $result = Register-WtwT3Project -ProjectPath $script:WorkPath -PrettyName 'Nope'
        $result.Status | Should -Be 'skipped'
        $result.Reason | Should -Match 'running'

        (& $script:Sqlite $script:StorePath 'SELECT COUNT(*) FROM orchestration_events') |
            Should -Be '0'
    }

    It 'refuses to write when the store schema has drifted, naming the missing column' {
        & $script:Sqlite $script:StorePath 'ALTER TABLE orchestration_events DROP COLUMN metadata_json'

        $result = Register-WtwT3Project -ProjectPath $script:WorkPath -PrettyName 'Nope'
        $result.Status | Should -Be 'skipped'
        $result.Reason | Should -Match 'schema changed'
        $result.Reason | Should -Match 'metadata_json'
    }

    # T3 keeps its store in WAL mode. A read-only SQLite connection has to be
    # able to create the `-shm` shared-memory file to read a WAL database, so
    # `sqlite3 -readonly` fails with "unable to open database file (14)" — both
    # while T3 holds the store and after it quits leaving a hot WAL behind. That
    # is what made `wtw t3` report schema drift against a perfectly good store.
    It 'reads a WAL-mode store that has no -shm file' {
        & $script:Sqlite $script:StorePath 'PRAGMA journal_mode=WAL' | Out-Null
        Remove-Item "$($script:StorePath)-shm" -Force -ErrorAction SilentlyContinue

        $result = Invoke-WtwT3Query -Sqlite $script:Sqlite -DatabasePath $script:StorePath `
            -Query 'SELECT COUNT(*) AS n FROM projection_projects'

        $result.Ok | Should -BeTrue -Because 'a WAL store must stay readable without a -shm file'
        $result.Rows[0].n | Should -Be 0
    }

    It 'reports an unreadable store as a read failure, not as schema drift' {
        $missing = Join-Path $script:StoreDir 'not-a-database.sqlite'
        'plain text, not sqlite' | Set-Content -Path $missing -NoNewline

        $schema = Test-WtwT3StateSchema -Sqlite $script:Sqlite -DatabasePath $missing
        $schema.Ok    | Should -BeFalse
        $schema.Error | Should -Match 'could not read'
        $schema.Error | Should -Not -Match 'schema changed'
    }

    It 'separates an empty result from a failed query' {
        $ok = Invoke-WtwT3Query -Sqlite $script:Sqlite -DatabasePath $script:StorePath `
            -Query 'SELECT project_id FROM projection_projects'
        $ok.Ok         | Should -BeTrue
        $ok.Rows.Count | Should -Be 0

        $bad = Invoke-WtwT3Query -Sqlite $script:Sqlite -DatabasePath $script:StorePath `
            -Query 'SELECT * FROM no_such_table'
        $bad.Ok    | Should -BeFalse
        $bad.Error | Should -Not -BeNullOrEmpty
    }

    It 'skips quietly when T3 Code has no store yet' {
        Mock Get-WtwT3StatePath { Join-Path $script:StoreDir 'absent.sqlite' }

        (Register-WtwT3Project -ProjectPath $script:WorkPath -PrettyName 'Nope').Status |
            Should -Be 'skipped'
    }
}

Describe 'T3 Code editor resolution' {
    It 'routes t3 aliases to the dedicated launcher type' {
        foreach ($alias in 't3', 't3code') {
            $editor = Resolve-WtwEditorCommand $alias
            $editor.type | Should -Be 't3'
            $editor.appNameCandidates | Should -Contain 'T3 Code (Alpha)'
        }
    }
}

Describe 'T3 sidebar grouping' {
    BeforeEach {
        $script:CsDir = Join-Path ([System.IO.Path]::GetTempPath()) "wtw-t3g-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $script:CsDir -Force | Out-Null
        $script:CsPath = Join-Path $script:CsDir 'client-settings.json'
        Mock Get-WtwT3ClientSettingsPath { $script:CsPath }
        Mock Get-WtwT3EnvironmentId { 'env-1' }
    }

    AfterEach {
        Remove-Item -Path $script:CsDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Repository grouping keys on the git remote, so sibling worktrees collapse
    # into one multi-member group that renders the repo name instead of each
    # project's title — which reads as "wtw's pretty name did nothing".
    It 'flags repository grouping, which hides per-worktree titles' {
        '{"sidebarProjectGroupingMode":"repository"}' | Set-Content -Path $script:CsPath -NoNewline
        Test-WtwT3GroupingHidesTitles | Should -BeTrue
    }

    It 'accepts separate grouping, where each worktree shows its own title' {
        '{"sidebarProjectGroupingMode":"separate"}' | Set-Content -Path $script:CsPath -NoNewline
        Test-WtwT3GroupingHidesTitles | Should -BeFalse
    }

    It 'treats an absent key as the repository default' {
        '{"wordWrap":true}' | Set-Content -Path $script:CsPath -NoNewline
        Test-WtwT3GroupingHidesTitles | Should -BeTrue
    }

    It 'stays quiet when there is no settings file or it is unreadable' {
        Test-WtwT3GroupingHidesTitles | Should -BeFalse
        'not json' | Set-Content -Path $script:CsPath -NoNewline
        Test-WtwT3GroupingHidesTitles | Should -BeFalse
    }

    # The key has to match T3's `Dx()` byte for byte or the override applies to
    # nothing: POSIX paths keep their case, Windows paths fold to lowercase
    # backslashes, and trailing separators are stripped on both.
    It 'builds the project key the way T3 does' {
        Get-WtwT3ProjectKey -WorkspaceRoot '/Users/sno/Repo' | Should -Be 'env-1:/Users/sno/Repo'
        ConvertTo-WtwT3NormalizedPath -Path '/Users/sno/Repo/'  | Should -Be '/Users/sno/Repo'
        ConvertTo-WtwT3NormalizedPath -Path 'C:/Users/Sno/Repo' | Should -Be 'c:\users\sno\repo'
        ConvertTo-WtwT3NormalizedPath -Path '\\srv\share\Repo\' | Should -Be '\\srv\share\repo'
        ConvertTo-WtwT3NormalizedPath -Path '/'                 | Should -Be '/'
    }

    It 'splits one worktree out without touching the global mode' {
        '{"sidebarProjectGroupingMode":"repository","wordWrap":true}' |
            Set-Content -Path $script:CsPath -NoNewline

        Set-WtwT3ProjectGroupingOverride -WorkspaceRoot '/Users/sno/Repo' | Should -Be 'set'

        $saved = Get-Content -Path $script:CsPath -Raw | ConvertFrom-Json
        $saved.sidebarProjectGroupingMode | Should -Be 'repository'
        $saved.wordWrap                   | Should -BeTrue
        $saved.sidebarProjectGroupingOverrides.'env-1:/Users/sno/Repo' | Should -Be 'separate'

        # Effective mode for that worktree is now 'separate'; others are untouched.
        Test-WtwT3GroupingHidesTitles -WorkspaceRoot '/Users/sno/Repo'  | Should -BeFalse
        Test-WtwT3GroupingHidesTitles -WorkspaceRoot '/Users/sno/Other' | Should -BeTrue
    }

    It 'never overwrites an override the user set themselves' {
        '{"sidebarProjectGroupingOverrides":{"env-1:/Users/sno/Repo":"repository"}}' |
            Set-Content -Path $script:CsPath -NoNewline

        Set-WtwT3ProjectGroupingOverride -WorkspaceRoot '/Users/sno/Repo' | Should -Be 'existing'

        $saved = Get-Content -Path $script:CsPath -Raw | ConvertFrom-Json
        $saved.sidebarProjectGroupingOverrides.'env-1:/Users/sno/Repo' | Should -Be 'repository'
    }

    It 'does not bootstrap a settings file T3 Code has not created' {
        Set-WtwT3ProjectGroupingOverride -WorkspaceRoot '/Users/sno/Repo' | Should -Be 'skipped'
        Test-Path $script:CsPath | Should -BeFalse
    }
}

Describe 'Set-WtwT3AddProjectBaseDirectory' {
    BeforeEach {
        $script:SettingsDir = Join-Path ([System.IO.Path]::GetTempPath()) "wtw-t3s-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $script:SettingsDir -Force | Out-Null
        $script:SettingsPath = Join-Path $script:SettingsDir 'settings.json'
        Mock Get-WtwT3SettingsPath { $script:SettingsPath }
    }

    AfterEach {
        Remove-Item -Path $script:SettingsDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'sets the picker directory while preserving nested settings' {
        '{"textGenerationModelSelection":{"provider":"claudeAgent","options":{"effort":"high"}}}' |
            Set-Content -Path $script:SettingsPath -NoNewline

        Set-WtwT3AddProjectBaseDirectory -Path $script:SettingsDir | Should -BeTrue

        $saved = Get-Content -Path $script:SettingsPath -Raw | ConvertFrom-Json
        $saved.addProjectBaseDirectory | Should -Be ([System.IO.Path]::GetFullPath($script:SettingsDir))
        $saved.textGenerationModelSelection.options.effort | Should -Be 'high'
    }

    It 'does not bootstrap a settings file T3 Code has not created' {
        Set-WtwT3AddProjectBaseDirectory -Path $script:SettingsDir | Should -BeFalse
        Test-Path $script:SettingsPath | Should -BeFalse
    }
}
