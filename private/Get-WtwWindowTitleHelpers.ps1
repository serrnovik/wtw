# Icon pool — deterministically assigned to each repo/branch via FNV hash.
# Keep this in a function instead of a script-scoped variable: PowerShell gives
# each dot-sourced file its own script scope, so a public command cannot safely
# read a variable initialized from this private file under StrictMode.
function Get-WtwIconPool {
    @(
    '💠', '🔶', '🔷', '🥜', '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇',
    '🍓', '🍈', '🍒', '🍑', '🍍', '🥝', '🥑', '🍅', '🍆', '🥒', '🥕', '🌽',
    '🌶', '🥔', '🍠', '🌰', '🍯', '🥐', '🍞', '🥖', '🧀', '🥚', '🍳', '🥓',
    '🥞', '🍗', '🍖', '🍕', '🍔', '🍟', '🥙', '🌮', '🌯', '🥗'
    )
}

function Get-WtwFNVHash {
    param([string] $InputString)
    [uint32] $prime = 16777619
    [uint32] $hash  = 2166136261
    foreach ($byte in [System.Text.Encoding]::UTF8.GetBytes($InputString)) {
        $hash = ($hash -bxor $byte) * $prime % 4294967296
    }
    return $hash
}

function Get-WtwNumberFromRange {
    param($range, [uint32] $value)
    return [int]([double]($range / [uint32]::MaxValue) * $value)
}
