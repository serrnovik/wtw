# Icon pool — deterministically assigned to each repo/branch via FNV hash
$script:_WtwIcons = @(
    '💠', '🔶', '🔷', '🥜', '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇',
    '🍓', '🍈', '🍒', '🍑', '🍍', '🥝', '🥑', '🍅', '🍆', '🥒', '🥕', '🌽',
    '🌶', '🥔', '🍠', '🌰', '🍯', '🥐', '🍞', '🥖', '🧀', '🥚', '🍳', '🥓',
    '🥞', '🍗', '🍖', '🍕', '🍔', '🍟', '🥙', '🌮', '🌯', '🥗'
)

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
