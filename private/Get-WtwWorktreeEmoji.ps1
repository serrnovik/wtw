function Get-WtwWorktreeEmojiPoolCodepoints {
    <#
    .SYNOPSIS
        Codepoints for worktree identity glyphs (Unicode 6–12, one scalar each).
    .DESCRIPTION
        Animals, plants, food, and objects that render as a single emoji on
        Windows, macOS, and Linux. No flags, ZWJ sequences, skin tones, or
        color-circle swatches. Keep this in a function: each private file has
        its own script scope.
    #>
    @(
        # Animals (Unicode 6.0)
        0x1F400, 0x1F401, 0x1F402, 0x1F403, 0x1F404, 0x1F405, 0x1F406, 0x1F407,
        0x1F408, 0x1F409, 0x1F40A, 0x1F40B, 0x1F40C, 0x1F40D, 0x1F40E, 0x1F40F,
        0x1F410, 0x1F411, 0x1F412, 0x1F413, 0x1F414, 0x1F415, 0x1F416, 0x1F417,
        0x1F418, 0x1F419, 0x1F41A, 0x1F41B, 0x1F41C, 0x1F41D, 0x1F41E, 0x1F41F,
        0x1F420, 0x1F421, 0x1F422, 0x1F423, 0x1F424, 0x1F425, 0x1F426, 0x1F427,
        0x1F428, 0x1F429, 0x1F42A, 0x1F42B, 0x1F42C, 0x1F42D, 0x1F42E, 0x1F42F,
        0x1F430, 0x1F431, 0x1F432, 0x1F433, 0x1F434, 0x1F435, 0x1F436, 0x1F437,
        0x1F438, 0x1F439, 0x1F43A, 0x1F43B, 0x1F43C, 0x1F43D, 0x1F43E,
        # Animals (Unicode 8–12)
        0x1F980, 0x1F981, 0x1F982, 0x1F983, 0x1F984, 0x1F985, 0x1F986, 0x1F987,
        0x1F988, 0x1F989, 0x1F98A, 0x1F98B, 0x1F98C, 0x1F98D, 0x1F98E, 0x1F990,
        0x1F991, 0x1F992, 0x1F993, 0x1F994, 0x1F995, 0x1F996, 0x1F997, 0x1F998,
        0x1F999, 0x1F99A, 0x1F99B, 0x1F99C, 0x1F99D, 0x1F99E, 0x1F99F, 0x1F9A5,
        0x1F9A6, 0x1F9A7, 0x1F9A8, 0x1F9A9, 0x1F9AA,
        # Plants / fruit
        0x1F330, 0x1F331, 0x1F332, 0x1F333, 0x1F334, 0x1F335, 0x1F337, 0x1F338,
        0x1F339, 0x1F33A, 0x1F33B, 0x1F33C, 0x1F33D, 0x1F340, 0x1F341, 0x1F342,
        0x1F343, 0x1F344, 0x1F345, 0x1F346, 0x1F347, 0x1F348, 0x1F349, 0x1F34A,
        0x1F34B, 0x1F34C, 0x1F34D, 0x1F34E, 0x1F34F, 0x1F350, 0x1F351, 0x1F352,
        0x1F353, 0x1F490, 0x1F951, 0x1F952, 0x1F954, 0x1F955, 0x1F95D, 0x1F965,
        0x1F966, 0x1F96C, 0x1F96D, 0x1F9C4, 0x1F9C5,
        # Food
        0x2615,  0x1F32D, 0x1F32E, 0x1F32F, 0x1F354, 0x1F355, 0x1F356, 0x1F357,
        0x1F35A, 0x1F35C, 0x1F35D, 0x1F35E, 0x1F35F, 0x1F360, 0x1F363, 0x1F364,
        0x1F366, 0x1F369, 0x1F36A, 0x1F36B, 0x1F36D, 0x1F36F, 0x1F370, 0x1F372,
        0x1F373, 0x1F375, 0x1F377, 0x1F37A, 0x1F37F, 0x1F382, 0x1F950, 0x1F956,
        0x1F957, 0x1F95A, 0x1F95E, 0x1F96F, 0x1F9C0, 0x1F9C1, 0x1F9C2, 0x1F9C6,
        0x1F9C7, 0x1F9C8, 0x1F9C9, 0x1F9CA,
        # Nature / objects / sport / music
        0x26A1,  0x26BD,  0x26BE,  0x26F3,  0x2B50,  0x2728,  0x1F308, 0x1F30A,
        0x1F30B, 0x1F315, 0x1F319, 0x1F31F, 0x1F381, 0x1F388, 0x1F389, 0x1F3A4,
        0x1F3A7, 0x1F3A8, 0x1F3AE, 0x1F3AF, 0x1F3B2, 0x1F3B3, 0x1F3B7, 0x1F3B8,
        0x1F3B9, 0x1F3BA, 0x1F3BB, 0x1F3BE, 0x1F3C0, 0x1F3C6, 0x1F3C8, 0x1F48E,
        0x1F4A1, 0x1F4A5, 0x1F4A7, 0x1F4AB, 0x1F4BB, 0x1F4D6, 0x1F4DA, 0x1F511,
        0x1F512, 0x1F514, 0x1F525, 0x1F527, 0x1F528, 0x1F52E, 0x1F680, 0x1F681,
        0x1F6A2, 0x1F6B2, 0x1F6F9, 0x1F9E9, 0x1F9ED, 0x1F9F1, 0x1F9F8, 0x1FA80,
        0x1FA81, 0x1FA82, 0x1FA90
    )
}

function Get-WtwWorktreeEmojiPool {
    <#
    .SYNOPSIS
        Identity-emoji strings. Walk with UTF-32 — never ``.ToCharArray()``.
    #>
    foreach ($cp in (Get-WtwWorktreeEmojiPoolCodepoints)) {
        [char]::ConvertFromUtf32($cp)
    }
}

function Get-WtwCompactRepoEmoji {
    <#
    .SYNOPSIS
        Repo prefix with whitespace removed so ``🎭 ☸️`` + ``🦔`` is ``🎭☸️🦔``.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Emoji,

        [AllowNull()]
        [object] $RepoEntry
    )

    if ($RepoEntry -and -not $PSBoundParameters.ContainsKey('Emoji')) {
        $Emoji = Get-WtwRepoEmoji -RepoEntry $RepoEntry
    }

    $normalized = ConvertTo-WtwNormalizedRepoEmoji $Emoji
    if (-not $normalized) { return $null }
    return ($normalized -replace '\s+', '')
}

function Get-WtwWorktreeEmojiSeed {
    <#
    .SYNOPSIS
        Canonical hash input: branch-safe task name, NFC, invariant lower-case.
    #>
    [CmdletBinding()]
    param([AllowNull()] [AllowEmptyString()] [string] $Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    $safe = ConvertTo-WtwBranchSafeName -Name $Name
    if ([string]::IsNullOrWhiteSpace($safe)) { return $null }
    return $safe.Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()
}

function Get-WtwDerivedWorktreeEmoji {
    <#
    .SYNOPSIS
        Deterministic pool pick from a worktree task name (SHA-256, little-endian).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name
    )

    $seed = Get-WtwWorktreeEmojiSeed -Name $Name
    if (-not $seed) { return $null }

    $pool = @(Get-WtwWorktreeEmojiPool)
    if ($pool.Count -eq 0) { return $null }

    $payload = [System.Text.Encoding]::UTF8.GetBytes("wtw-worktree-emoji:`n$seed")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($payload)
    } finally {
        $sha.Dispose()
    }

    # First 4 bytes as little-endian UInt32 so the index is endian-stable.
    [uint32] $indexBits = [uint32]$hash[0] `
        -bor ([uint32]$hash[1] -shl 8) `
        -bor ([uint32]$hash[2] -shl 16) `
        -bor ([uint32]$hash[3] -shl 24)
    $idx = [int]($indexBits % [uint32]$pool.Count)
    return $pool[$idx]
}

function Get-WtwWorktreeEmoji {
    <#
    .SYNOPSIS
        Stored override, else a glyph derived from the task (or pretty-name fallback).
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $WorktreeEntry,

        [AllowNull()]
        [AllowEmptyString()]
        [string] $TaskName,

        [AllowNull()]
        [AllowEmptyString()]
        [string] $Name
    )

    $override = ConvertTo-WtwNormalizedRepoEmoji (Get-WtwPropertyValue -Object $WorktreeEntry -Name 'emoji')
    if ($override) { return $override }

    if (-not [string]::IsNullOrWhiteSpace($TaskName)) {
        $derived = Get-WtwDerivedWorktreeEmoji -Name $TaskName
        if ($derived) { return $derived }
    }

    $fallback = Get-WtwNameWithoutColorCircle -Name $Name
    if ([string]::IsNullOrWhiteSpace($fallback) -and $WorktreeEntry) {
        $fallback = Get-WtwNameWithoutColorCircle (Get-WtwPropertyValue -Object $WorktreeEntry -Name 'prettyName')
    }
    if ([string]::IsNullOrWhiteSpace($fallback)) { return $null }
    return Get-WtwDerivedWorktreeEmoji -Name $fallback
}

function Set-WtwWorktreeEmojiProperty {
    <#
    .SYNOPSIS
        Write or clear a worktree emoji override. ``none`` / ``auto`` restores derived.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $WorktreeEntry,

        [AllowNull()]
        [AllowEmptyString()]
        [object] $Emoji
    )

    $normalized = ConvertTo-WtwNormalizedRepoEmoji $Emoji
    if ($normalized) {
        $WorktreeEntry | Add-Member -NotePropertyName 'emoji' -NotePropertyValue $normalized -Force
    } elseif ((Get-WtwPropertyNames -Object $WorktreeEntry) -contains 'emoji') {
        $WorktreeEntry.PSObject.Properties.Remove('emoji')
    }
    return $normalized
}

function Format-WtwWorktreeDisplayName {
    <#
    .SYNOPSIS
        ``{repoEmojiCompact}{worktreeEmoji} {baseName}`` with no space between emojis.
    .DESCRIPTION
        Strips leading color circles from the stored pretty name so SourceGit /
        cmux / T3 titles are identity emojis, not swatches. Does not strip a
        custom leading pool emoji (``🏀 PF037`` stays). Main checkout is repo-only
        and does not use this helper.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Name,

        [AllowNull()]
        [AllowEmptyString()]
        [string] $TaskName,

        [AllowNull()]
        [object] $WorktreeEntry,

        [AllowNull()]
        [object] $RepoEntry,

        [AllowNull()]
        [AllowEmptyString()]
        [string] $WorktreeEmoji,

        [AllowNull()]
        [AllowEmptyString()]
        [string] $RepoEmoji
    )

    if ($WorktreeEntry -and [string]::IsNullOrWhiteSpace($Name)) {
        $Name = Get-WtwPropertyValue -Object $WorktreeEntry -Name 'prettyName'
    }

    if (-not $PSBoundParameters.ContainsKey('WorktreeEmoji') -or $null -eq $WorktreeEmoji) {
        $WorktreeEmoji = Get-WtwWorktreeEmoji -WorktreeEntry $WorktreeEntry -TaskName $TaskName -Name $Name
    }

    $base = Get-WtwNameWithoutColorCircle -Name $Name
    if ([string]::IsNullOrWhiteSpace($base) -and -not [string]::IsNullOrWhiteSpace($TaskName)) {
        $base = $TaskName
    }

    $repoCompact = if ($PSBoundParameters.ContainsKey('RepoEmoji')) {
        Get-WtwCompactRepoEmoji -Emoji $RepoEmoji
    } else {
        Get-WtwCompactRepoEmoji -RepoEntry $RepoEntry
    }

    $prefix = if ($WorktreeEmoji) {
        if ($repoCompact) { "$repoCompact$WorktreeEmoji " } else { "$WorktreeEmoji " }
    } else {
        $null
    }

    $remainder = $base
    if ($prefix -and -not [string]::IsNullOrWhiteSpace($base) -and $base.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
        $remainder = $base.Substring($prefix.Length)
    } elseif ($WorktreeEmoji -and $repoCompact -and -not [string]::IsNullOrWhiteSpace($base)) {
        $tight = "$repoCompact$WorktreeEmoji"
        if ($base.StartsWith($tight, [System.StringComparison]::Ordinal)) {
            $remainder = $base.Substring($tight.Length).TrimStart()
        }
    }

    $remainder = ConvertTo-WtwHumanizedLabel -Name $remainder -Slug $TaskName

    if (-not $WorktreeEmoji) {
        if (-not [string]::IsNullOrWhiteSpace($remainder)) { return $remainder }
        if (-not [string]::IsNullOrWhiteSpace($Name)) { return $Name }
        return $base
    }

    if ([string]::IsNullOrWhiteSpace($remainder)) { return $prefix.TrimEnd() }
    return "$prefix$remainder"
}
