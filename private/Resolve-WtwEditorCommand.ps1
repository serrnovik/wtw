function Resolve-WtwEditorCommand {
    param([string] $Name)

    if (-not $Name) { return $null }

    $editors = @(
        @{ prefixes = @('cursor', 'cur'); cmd = 'cursor' }
        @{ prefixes = @('code', 'co'); cmd = 'code' }
        @{ prefixes = @('antigravity', 'anti', 'ag'); cmd = 'antigravity' }
        @{ prefixes = @('sourcegit', 'sgit', 'sg'); cmd = 'sourcegit' }
    )

    # 1. Exact + prefix match
    foreach ($editor in $editors) {
        foreach ($prefix in $editor.prefixes) {
            if ($prefix -eq $Name -or $prefix.StartsWith($Name)) {
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
    # Tied or no match — fall through to target resolution
    return $null
}
