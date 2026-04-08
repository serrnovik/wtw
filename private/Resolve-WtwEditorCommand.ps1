function Resolve-WtwEditorCommand {
    param([string] $Name)

    if (-not $Name) { return $null }

    # Exact + prefix matches for each editor
    $editors = @(
        @{ prefixes = @('cursor', 'cur'); cmd = 'cursor' }
        @{ prefixes = @('code', 'co'); cmd = 'code' }
        @{ prefixes = @('antigravity', 'anti', 'ag'); cmd = 'antigravity' }
        @{ prefixes = @('sourcegit', 'sgit', 'sg'); cmd = 'sourcegit' }
    )

    foreach ($editor in $editors) {
        foreach ($prefix in $editor.prefixes) {
            if ($prefix -eq $Name -or $prefix.StartsWith($Name)) {
                return $editor.cmd
            }
        }
    }

    return $null
}
