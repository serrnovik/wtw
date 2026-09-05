function ConvertTo-WtwNormalizedRepoEmoji {
    <#
    .SYNOPSIS
        Normalize a repo-level emoji prefix, or $null to clear.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [object] $Emoji
    )

    if ($null -eq $Emoji) { return $null }
    if ($Emoji -is [switch]) { return $null }

    $trimmed = ("$Emoji" -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return $null }
    if ($trimmed -in @('-', 'none', 'off', 'clear')) { return $null }
    return $trimmed
}

function Test-WtwEmojiArgument {
    <#
    .SYNOPSIS
        Reject ``--emoji`` used as a switch (no value).
    #>
    [CmdletBinding()]
    param([AllowNull()] [object] $Emoji)

    if ($Emoji -is [switch]) {
        Write-Error '--emoji requires a value (emoji string, or - / none to clear).'
        return $false
    }
    return $true
}

function Get-WtwRepoEmoji {
    <#
    .SYNOPSIS
        Read the optional repo-level emoji prefix from a registry entry.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $RepoEntry
    )

    return ConvertTo-WtwNormalizedRepoEmoji (Get-WtwPropertyValue -Object $RepoEntry -Name 'emoji')
}

function Format-WtwRepoDisplayName {
    <#
    .SYNOPSIS
        Prefix a repo registry key with its optional emoji (SourceGit / list).
    .DESCRIPTION
        Worktrees keep their color-circle pretty names. This is repo-only:
        ``🎸 snowmain1``, ``🎭 ☸️ tn1-gitops``.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

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
    if (-not $normalized) { return $Name }
    return "$normalized $Name"
}

function Set-WtwRepoEmojiProperty {
    <#
    .SYNOPSIS
        Write or clear the emoji note-property on a repo registry entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $RepoEntry,

        [AllowNull()]
        [AllowEmptyString()]
        [object] $Emoji
    )

    $normalized = ConvertTo-WtwNormalizedRepoEmoji $Emoji
    if ($normalized) {
        $RepoEntry | Add-Member -NotePropertyName 'emoji' -NotePropertyValue $normalized -Force
    } elseif ((Get-WtwPropertyNames -Object $RepoEntry) -contains 'emoji') {
        $RepoEntry.PSObject.Properties.Remove('emoji')
    }
    return $normalized
}
