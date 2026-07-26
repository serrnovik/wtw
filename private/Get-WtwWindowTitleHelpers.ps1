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
    param(
        [int] $Range,
        [uint32] $Value
    )

    if ($Range -le 0) {
        throw 'Range must be greater than zero.'
    }

    # Divide by MaxValue + 1 so every uint32 maps into [0, Range). Casting a
    # scaled value directly to [int] rounds in PowerShell and can produce Range,
    # which is one past the last valid array index.
    return [int][Math]::Floor(
        ([double]$Value / ([double][uint32]::MaxValue + 1.0)) * $Range
    )
}
