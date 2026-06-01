function Resolve-WtwTerminalWorkspaceMetadata {
    <#
    .SYNOPSIS
        Resolve shared terminal workspace metadata for cmux/wmux-style launchers.
    .DESCRIPTION
        Produces a cwd, display title, color, and status value from a resolved wtw
        target. The title includes the wtw color-circle prefix when a color is
        available, which keeps terminal workspaces recognizable even for tools
        that do not expose a separate color argument.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Target
    )

    $dir = if ($Target.WorktreeEntry) { $Target.WorktreeEntry.path } else { $Target.RepoEntry.mainPath }
    if (-not $dir) { return $null }

    $fullDir = [System.IO.Path]::GetFullPath($dir)
    $color = $null
    $baseName = $null
    $statusValue = if ($Target.TaskName) { "$($Target.RepoName)/$($Target.TaskName)" } else { $Target.RepoName }

    if ($Target.WorktreeEntry) {
        if ($Target.WorktreeEntry.PSObject.Properties.Name -contains 'color') {
            $color = $Target.WorktreeEntry.color
        }

        if ($Target.WorktreeEntry.PSObject.Properties.Name -contains 'prettyName' -and $Target.WorktreeEntry.prettyName) {
            $baseName = $Target.WorktreeEntry.prettyName
        } elseif ($Target.TaskName) {
            $baseName = $Target.TaskName
        }
    } else {
        $colorKey = "$($Target.RepoName)/main"
        $colors = Get-WtwColors
        $assignment = $colors.assignments.PSObject.Properties[$colorKey]
        if ($assignment) {
            $color = $assignment.Value
        }

        $aliases = Get-WtwRepoAliases $Target.RepoEntry
        if ($aliases -and $aliases.Count -gt 0) {
            $baseName = @($aliases)[0]
        } elseif ($Target.RepoName) {
            $baseName = $Target.RepoName
        }
    }

    if (-not $baseName) {
        $baseName = Split-Path $fullDir -Leaf
    }

    $prettyName = if ($color) {
        Format-WtwPrettyNameWithCircle -Hex $color -Name $baseName
    } else {
        $baseName
    }

    return [PSCustomObject]@{
        Path        = $fullDir
        PrettyName  = $prettyName
        Color       = $color
        StatusValue = $statusValue
    }
}
