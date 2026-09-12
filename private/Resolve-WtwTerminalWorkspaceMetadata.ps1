function Resolve-WtwTerminalWorkspaceMetadata {
    <#
    .SYNOPSIS
        Resolve shared terminal workspace metadata for cmux/wmux-style launchers.
    .DESCRIPTION
        Produces a cwd, display title, color, and status value from a resolved wtw
        target.

        Worktrees compose ``{repoEmoji}{worktreeEmoji} {name}`` (no space
        between glyphs), using the worktree's form name (not an alias). Derived
        slugs get dashes/underscores turned into spaces unless ``--name`` was
        set (``🎸🐕 NTB real dogfood``). Main-repo titles use the registry key,
        prefixed with the optional repo emoji (``🎸 snowmain1``). A
        main-checkout color assignment, when present, still prepends the
        color-circle.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Target
    )

    $worktreeEntry = Get-WtwPropertyValue -Object $Target -Name 'WorktreeEntry'
    $repoEntry = Get-WtwPropertyValue -Object $Target -Name 'RepoEntry'
    $taskName = Get-WtwPropertyValue -Object $Target -Name 'TaskName'
    $repoName = Get-WtwPropertyValue -Object $Target -Name 'RepoName'

    $dir = if ($worktreeEntry) {
        Get-WtwPropertyValue -Object $worktreeEntry -Name 'path'
    } else {
        Get-WtwPropertyValue -Object $repoEntry -Name 'mainPath'
    }
    if (-not $dir) { return $null }

    $fullDir = [System.IO.Path]::GetFullPath($dir)
    $color = $null
    $prettyName = $null
    $statusValue = if ($taskName) { "$repoName/$taskName" } else { $repoName }

    if ($worktreeEntry) {
        $color = Get-WtwPropertyValue -Object $worktreeEntry -Name 'color'
        $prettyName = Get-WtwPropertyValue -Object $worktreeEntry -Name 'prettyName'
        if (-not $prettyName -and $taskName) {
            $prettyName = $taskName
            if ($color) {
                $prettyName = Format-WtwPrettyNameWithCircle -Hex $color -Name $prettyName
            }
        }
        $prettyName = Format-WtwWorktreeDisplayName `
            -Name $prettyName `
            -TaskName $taskName `
            -WorktreeEntry $worktreeEntry `
            -RepoEntry $repoEntry
    } else {
        $colorKey = if ($repoName) { "$repoName/main" } else { $null }
        if ($colorKey) {
            $colors = Get-WtwColors
            $assignments = Get-WtwPropertyValue -Object $colors -Name 'assignments'
            $color = Get-WtwPropertyValue -Object $assignments -Name $colorKey
        }

        $baseName = if ($repoName) { $repoName } else { Split-Path $fullDir -Leaf }
        $prettyName = Format-WtwRepoDisplayName -Name $baseName -RepoEntry $repoEntry
        if ($color) {
            $prettyName = Format-WtwPrettyNameWithCircle -Hex $color -Name $prettyName
        }
    }

    if (-not $prettyName) {
        $prettyName = Split-Path $fullDir -Leaf
        if (-not $worktreeEntry) {
            $prettyName = Format-WtwRepoDisplayName -Name $prettyName -RepoEntry $repoEntry
        }
    }

    return [PSCustomObject]@{
        Path        = $fullDir
        PrettyName  = $prettyName
        Color       = $color
        StatusValue = $statusValue
    }
}
