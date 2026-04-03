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
        $aliases = Get-WtwRepoAliases $repoEntry
        if ($Repo -and $Repo -notin $aliases -and $name -ne $Repo) { continue }

        $wsFile = $repoEntry.templateWorkspace
        $wsDisplay = if ($wsFile -and (Test-Path $wsFile)) { Split-Path $wsFile -Leaf } else { '-' }

        # Main entry
        $items += [PSCustomObject]@{
            Kind      = 'repo'
            Repo      = $name
            Aliases   = ($aliases -join ', ')
            Branch    = (git -C $repoEntry.mainPath branch --show-current 2>$null) ?? '?'
            Color     = (Get-WtwColors).assignments."$name/main" ?? '-'
            Path      = $repoEntry.mainPath
            Workspace = $wsDisplay
        }

        # Worktrees
        if ($repoEntry.worktrees) {
            foreach ($taskName in $repoEntry.worktrees.PSObject.Properties.Name) {
                $wt = $repoEntry.worktrees.$taskName
                $exists = Test-Path $wt.path
                $wtWsDisplay = if ($wt.workspace -and (Test-Path $wt.workspace)) { Split-Path $wt.workspace -Leaf } else { '-' }
                $wtAliases = ($aliases | ForEach-Object { "$_-$taskName" }) -join ', '
                $pathDisplay = if ($exists) { $wt.path } else { "$($wt.path) (MISSING)" }

                $items += [PSCustomObject]@{
                    Kind      = '  wt'
                    Repo      = ''
                    Aliases   = $wtAliases
                    Branch    = $wt.branch
                    Color     = $wt.color ?? '-'
                    Path      = $pathDisplay
                    Workspace = $wtWsDisplay
                }
            }
        }
    }

    Write-Host ''
    Format-WtwTable $items @('Kind', 'Repo', 'Aliases', 'Branch', 'Color', 'Path', 'Workspace')
    Write-Host ''
}
