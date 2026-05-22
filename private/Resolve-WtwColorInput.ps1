$script:WtwColorNamePath = $null
$script:WtwColorNameIndex = $null

function Get-WtwColorNameIndex {
    <#
    .SYNOPSIS
        Lazy-load the bundled color-name → hex lookup table.
    .DESCRIPTION
        Parses both bundled CSVs once and caches a hashtable keyed by the
        normalized name (lowercased, only [a-z0-9]). HTML standard names load
        FIRST so canonical names (navy, forestgreen) win over creative ones
        with the same key from the larger 2.8k-color list.
    #>
    if ($script:WtwColorNameIndex) { return $script:WtwColorNameIndex }

    $assetsDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets'
    $sources = @(
        @{ Path = (Join-Path $assetsDir 'colornames.html.csv'); NameCol = 'name'; HexCol = 'hex' },
        @{ Path = (Join-Path $assetsDir 'colornames.csv');      NameCol = 'name'; HexCol = 'hex' }
    )
    $idx = @{}
    foreach ($src in $sources) {
        if (-not (Test-Path $src.Path)) { continue }
        try {
            foreach ($r in (Import-Csv -Path $src.Path)) {
                $name = $r.($src.NameCol)
                $hex  = $r.($src.HexCol)
                if (-not $name -or -not $hex) { continue }
                $key = ($name.ToLowerInvariant() -replace '[^a-z0-9]', '')
                if ($key -and -not $idx.ContainsKey($key)) {
                    $idx[$key] = $hex
                }
            }
        } catch { }
    }
    $script:WtwColorNameIndex = $idx
    return $idx
}

function Resolve-WtwColorInput {
    <#
    .SYNOPSIS
        Normalize a color argument to a #rrggbb hex string.
    .DESCRIPTION
        Accepts 'random' (pick max-contrast), '#rrggbb' or 'rrggbb' (hex literal),
        or a color name resolved against the bundled name table (case-insensitive,
        ignores spaces/hyphens/underscores/parentheses). Returns $null when input
        is empty or unresolvable.
    .PARAMETER Color
        The user-supplied color argument.
    .PARAMETER ExcludeKey
        Passed through to Find-WtwContrastColor when Color is 'random'.
    #>
    param(
        [string] $Color,
        [string] $ExcludeKey
    )

    if ([string]::IsNullOrWhiteSpace($Color)) { return $null }
    $trimmed = $Color.Trim()

    if ($trimmed -ieq 'random') {
        $colors = Get-WtwColors
        return (Find-WtwContrastColor $colors -ExcludeKey $ExcludeKey)
    }
    if ($trimmed -match '^#?[0-9a-fA-F]{6}$') {
        return $(if ($trimmed.StartsWith('#')) { $trimmed.ToLowerInvariant() } else { '#' + $trimmed.ToLowerInvariant() })
    }

    # Named color lookup
    $idx = Get-WtwColorNameIndex
    $key = ($trimmed.ToLowerInvariant() -replace '[^a-z0-9]', '')
    if ($key -and $idx.ContainsKey($key)) {
        return $idx[$key].ToLowerInvariant()
    }

    return $null
}
