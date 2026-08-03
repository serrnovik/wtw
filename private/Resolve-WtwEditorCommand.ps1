function Resolve-WtwEditorCommand {
    param([string] $Name)

    if (-not $Name) { return $null }

    $editors = @(
        @{ prefixes = @('cursor', 'cur'); cmd = 'cursor' }
        @{ prefixes = @('code', 'co'); cmd = 'code' }
        @{ prefixes = @('antigravity', 'anti', 'ag'); cmd = 'antigravity' }
        @{ prefixes = @('windsurf', 'wind', 'ws'); cmd = 'windsurf' }
        @{ prefixes = @('codium', 'vscodium'); cmd = 'codium' }
        # SourceGit — cross-platform. Pass repo dir as positional argv; SourceGit's IPC channel
        # routes a second-instance launch to the running one (see src/App.axaml.cs TryLaunchAsNormal).
        # macArgsViaCli=true → uses `open -n -a App --args <dir>` so argv actually carries the path.
        @{ prefixes = @('sourcegit', 'sgit', 'sg'); type = 'macapp';
           appName = 'SourceGit'; appNameCandidates = @('SourceGit'); macArgsViaCli = $true;
           winCmd = 'SourceGit'; linuxCmd = 'sourcegit' }
        # macOS open-app style — always opens directory, uses: open -a "AppName" <dir>
        # appNameCandidates: ordered list tried at runtime so name changes (Alpha→Beta→stable) work automatically
        @{ prefixes = @('chatgpt', 'cgpt', 'codex'); type = 'codex'; appName = 'ChatGPT'; cmd = 'codex'; appNameCandidates = @('ChatGPT', 'Codex') }
        # Factory Droid CLI — `factory` is the long-form alias for the `droid` command.
        @{ prefixes = @('droid', 'factory'); cmd = 'droid' }
        @{ prefixes = @('cmux', 'cm');          type = 'cmux';   appName = 'cmux';        cmd = 'cmux' }
        @{ prefixes = @('wmux', 'wm');          type = 'wmux';   appName = 'wmux';        cmd = 'wmux' }
        @{ prefixes = @('claude', 'cowork');    type = 'macapp'; appName = 'Claude';      appNameCandidates = @('Claude') }
        # Claude Code ships inside the Claude desktop app, not as its own bundle —
        # `claude://code/new?folder=<dir>` starts a chat rooted at the worktree.
        @{ prefixes = @('claudecode', 'ccode'); type = 'claudecode'; appName = 'Claude Code'; appNameCandidates = @('Claude') }
        @{ prefixes = @('t3', 't3code');        type = 'macapp'; appName = 'T3 Code';     appNameCandidates = @('T3 Code', 'T3 Code (Alpha)', 'T3 Code (Beta)') }
        # Superset — find matching workspace and open Superset app, or print hints
        @{ prefixes = @('ss', 'superset', 'supersetsh'); type = 'superset'; appName = 'Superset' }
    )

    # 1. Exact + prefix match
    foreach ($editor in $editors) {
        foreach ($prefix in $editor.prefixes) {
            if ($prefix -eq $Name -or $prefix.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($editor.ContainsKey('type')) {
                    $result = @{ type = $editor.type; appName = $editor.appName }
                    if ($editor.ContainsKey('cmd'))               { $result.cmd               = $editor.cmd }
                    if ($editor.ContainsKey('appNameCandidates')) { $result.appNameCandidates = $editor.appNameCandidates }
                    if ($editor.ContainsKey('winCmd'))        { $result.winCmd        = $editor.winCmd }
                    if ($editor.ContainsKey('linuxCmd'))      { $result.linuxCmd      = $editor.linuxCmd }
                    if ($editor.ContainsKey('macArgsViaCli')) { $result.macArgsViaCli = $editor.macArgsViaCli }
                    return $result
                }
                return $editor.cmd
            }
        }
    }

    # 2. Fuzzy match
    # Avoid fuzzy-matching arbitrary short commands (e.g. "vim") to two-letter
    # editor aliases such as "cm" or "co". Exact alias matching above still
    # handles those shortcuts.
    $allNames = $editors | ForEach-Object { $_.prefixes } | ForEach-Object { $_ } | Where-Object { $_.Length -ge 3 }
    $fuzzy = Resolve-WtwFuzzyMatch $Name $allNames
    if ($fuzzy.Match) {
        return (Resolve-WtwEditorCommand $fuzzy.Match)
    }
    # Tied or no match - fall through to target resolution
    return $null
}
