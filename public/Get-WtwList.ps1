function Get-WtwList {
    [CmdletBinding()]
    param(
        [string] $Repo
    )

    $registry = Get-WtwRegistry
    $repoNames = $registry.repos.PSObject.Properties.Name

    if (-not $repoNames -or $repoNames.Count -eq 0) {
        Write-Host '  No repos registered. Run "wtw init" inside a repo.' -ForegroundColor Yellow
        return
    }

    $items = @()

    foreach ($name in $repoNames) {
        $repoEntry = $registry.repos.$name
        if ($Repo -and $repoEntry.alias -ne $Repo -and $name -ne $Repo) { continue }

        # Main entry
        $items += [PSCustomObject]@{
            Repo      = $name
            Alias     = $repoEntry.alias
            Task      = '(main)'
            Branch    = (git -C $repoEntry.mainPath branch --show-current 2>$null) ?? '?'
            Path      = $repoEntry.mainPath
            Color     = (Get-WtwColors).assignments."$name/main" ?? '-'
            Workspace = $repoEntry.templateWorkspace ?? '-'
        }

        # Worktrees
        if ($repoEntry.worktrees) {
            foreach ($taskName in $repoEntry.worktrees.PSObject.Properties.Name) {
                $wt = $repoEntry.worktrees.$taskName
                $exists = Test-Path $wt.path
                $items += [PSCustomObject]@{
                    Repo      = ''
                    Alias     = ''
                    Task      = $taskName
                    Branch    = $wt.branch
                    Path      = if ($exists) { $wt.path } else { "$($wt.path) (MISSING)" }
                    Color     = $wt.color ?? '-'
                    Workspace = if ($wt.workspace -and (Test-Path $wt.workspace)) { Split-Path $wt.workspace -Leaf } else { '-' }
                }
            }
        }
    }

    Write-Host ''
    Format-WtwTable $items @('Repo', 'Alias', 'Task', 'Branch', 'Color', 'Workspace')
    Write-Host ''
}
