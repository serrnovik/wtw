function Resolve-WtwEditorCommand {
    param([string] $Name)

    if (-not $Name) { return $null }

    $editors = @(
        @{ prefixes = @('cursor', 'cur'); cmd = 'cursor' }
        @{ prefixes = @('code', 'co'); cmd = 'code' }
        @{ prefixes = @('antigravity', 'anti', 'ag'); cmd = 'antigravity' }
        @{ prefixes = @('windsurf', 'wind', 'ws'); cmd = 'windsurf' }
        @{ prefixes = @('codium', 'vscodium'); cmd = 'codium' }
        @{ prefixes = @('sourcegit', 'sgit', 'sg'); cmd = 'sourcegit' }
        # macOS open-app style — always opens directory, uses: open -a "AppName" <dir>
        @{ prefixes = @('codex');                 type = 'macapp'; appName = 'Codex' }
        @{ prefixes = @('claude', 'cowork');      type = 'macapp'; appName = 'Claude' }
        @{ prefixes = @('claudecode', 'ccode');   type = 'macapp'; appName = 'Claude Code' }
        @{ prefixes = @('t3', 't3code');          type = 'macapp'; appName = 'T3 Code (Alpha)' }
        # Superset — find matching workspace and open Superset app, or print hints
        @{ prefixes = @('ss', 'superset', 'supersetsh'); type = 'superset'; appName = 'Superset' }
    )

    # 1. Exact + prefix match
    foreach ($editor in $editors) {
        foreach ($prefix in $editor.prefixes) {
            if ($prefix -eq $Name -or $prefix.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($editor.ContainsKey('type')) {
                    return @{ type = $editor.type; appName = $editor.appName }
                }
                return $editor.cmd
            }
        }
    }

    # 2. Fuzzy match
    $allNames = $editors | ForEach-Object { $_.prefixes } | ForEach-Object { $_ }
    $fuzzy = Resolve-WtwFuzzyMatch $Name $allNames
    if ($fuzzy.Match) {
        return (Resolve-WtwEditorCommand $fuzzy.Match)
    }
    # Tied or no match - fall through to target resolution
    return $null
}
