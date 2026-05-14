function Get-WtwEllipsisText {
    <#
    .SYNOPSIS
        Truncate a string for terminal display with an ellipsis.
    #>
    param(
        [string] $Text,
        [int] $MaxLength,
        [ValidateSet('End', 'Middle')]
        [string] $Mode = 'End'
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    if ($Text.Length -le $MaxLength) {
        return $Text
    }

    if ($MaxLength -lt 2) {
        return $Text.Substring(0, [Math]::Min($MaxLength, $Text.Length))
    }

    if ($Mode -eq 'End') {
        return $Text.Substring(0, $MaxLength - 1) + [char]0x2026
    }

    if ($MaxLength -lt 5) {
        return $Text.Substring(0, $MaxLength)
    }

    $innerLength = $MaxLength - 3
    $leftCount = [Math]::Floor($innerLength / 2)
    $rightCount = $innerLength - $leftCount
    return $Text.Substring(0, $leftCount) + [char]0x2026 + $Text.Substring($Text.Length - $rightCount)
}

function ConvertTo-WtwShortDisplayPath {
    <#
    .SYNOPSIS
        Shorten an absolute path for list output (HOME → ~, optional middle ellipsis).
    #>
    param(
        [string] $Path,
        [int] $MaxLength = 48
    )

    if ([string]::IsNullOrEmpty($Path)) {
        return $Path
    }

    $missingSuffix = ''
    if ($Path -match ' \(MISSING\)$') {
        $missingSuffix = ' (MISSING)'
        $Path = $Path -replace ' \(MISSING\)$', ''
    }

    $homeDirectory = $HOME
    $displayPath = $Path
    if ($homeDirectory -and $Path.StartsWith($homeDirectory, [StringComparison]::Ordinal)) {
        $displayPath = '~' + $Path.Substring($homeDirectory.Length)
    }

    $budgetForPath = $MaxLength - $missingSuffix.Length
    if ($budgetForPath -lt 8) {
        $budgetForPath = 8
    }

    $truncatedPath = Get-WtwEllipsisText -Text $displayPath -MaxLength $budgetForPath -Mode Middle
    return $truncatedPath + $missingSuffix
}

function Get-WtwNarrowAliasesColumn {
    <#
    .SYNOPSIS
        Build the Aliases column value for compact list mode.
    #>
    param(
        [string] $AliasesJoined,
        [string] $Kind
    )

    $normalizedAliases = $AliasesJoined -replace ', ', "`n"
    $aliasParts = @(
        ($normalizedAliases -split "`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )

    if ($aliasParts.Count -eq 0) {
        return ''
    }

    $isWorktreeRow = $Kind -eq 'wt'
    if ($isWorktreeRow) {
        return $aliasParts[0]
    }

    if ($aliasParts.Count -le 2) {
        return ($aliasParts -join "`n")
    }

    $remainingAliasCount = $aliasParts.Count - 2
    return "$($aliasParts[0])`n$($aliasParts[1])`n(+$remainingAliasCount)"
}

function Get-WtwListRowsForTable {
    <#
    .SYNOPSIS
        Map full registry rows to table rows (compact vs wide).
    #>
    param(
        [array] $FullItems,
        [switch] $Wide
    )

    $taskLimitCompact   = 22
    $aliasLimitCompact  = 18
    $branchLimitCompact = 22
    $pathMaxCompact     = 26

    foreach ($entry in $FullItems) {
        if ($Wide) {
            $entry
            continue
        }

        $narrowTask    = Get-WtwEllipsisText -Text $entry.Task   -MaxLength $taskLimitCompact   -Mode End
        $narrowBranch  = Get-WtwEllipsisText -Text $entry.Branch -MaxLength $branchLimitCompact -Mode End
        $narrowPath    = ConvertTo-WtwShortDisplayPath -Path $entry.Path -MaxLength $pathMaxCompact
        $rawAlias      = Get-WtwNarrowAliasesColumn -AliasesJoined $entry.Aliases -Kind $entry.Kind
        $narrowAliases = if ($entry.Kind -eq 'wt') {
            Get-WtwEllipsisText -Text $rawAlias -MaxLength $aliasLimitCompact -Mode End
        } else {
            $rawAlias
        }

        [PSCustomObject]@{
            Kind    = $entry.Kind
            Repo    = $entry.Repo
            Task    = $narrowTask
            Aliases = $narrowAliases
            Branch  = $narrowBranch
            Color   = $entry.Color
            Path    = $narrowPath
            Created = $entry.Created
        }
        # Workspace omitted from compact; use --wide to see it
    }
}
