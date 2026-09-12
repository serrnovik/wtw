function ConvertTo-WtwComparableSlug {
    <#
    .SYNOPSIS
        Strip dashes, underscores, and whitespace so a task slug and a display
        label can be compared (``NTB-real-dogfood`` vs ``NTB real dogfood``).
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ($Value.Trim() -replace '[-_\s]+', '').ToLowerInvariant()
}

function Test-WtwDerivedLabel {
    <#
    .SYNOPSIS
        True when a display label is the task/repo slug (not a custom --name).
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Label,

        [AllowNull()]
        [AllowEmptyString()]
        [string] $Slug
    )

    if ([string]::IsNullOrWhiteSpace($Slug)) { return $true }
    if ([string]::IsNullOrWhiteSpace($Label)) { return $true }
    return (ConvertTo-WtwComparableSlug -Value $Label) -eq (ConvertTo-WtwComparableSlug -Value $Slug)
}

function ConvertTo-WtwHumanizedLabel {
    <#
    .SYNOPSIS
        Replace dashes/underscores with spaces on derived names only.
    .DESCRIPTION
        Task and repo slugs (``NTB-real-dogfood``) become ``NTB real dogfood``
        in muxer / SourceGit titles. A custom ``--name`` that is not the same
        slug is left unchanged, including any dashes the user typed.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Name,

        [AllowNull()]
        [AllowEmptyString()]
        [string] $Slug,

        [switch] $Specified
    )

    $base = Get-WtwNameWithoutColorCircle -Name $Name
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $Slug }
    if ([string]::IsNullOrWhiteSpace($base)) { return $base }

    $trimmed = $base.Trim()
    if ($Specified) { return $trimmed }
    if ($Slug -and -not (Test-WtwDerivedLabel -Label $trimmed -Slug $Slug)) {
        return $trimmed
    }

    return (($trimmed -replace '[-_]+', ' ') -replace '\s+', ' ').Trim()
}
