function Get-WtwList {
    [CmdletBinding()]
    param(
        [string] $Repo,

        [Alias('d')]
        [switch] $Detailed
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

    if ($Detailed) {
        Format-WtwDetailedList $items
    } else {
        Write-Host ''
        Format-WtwTable $items @('Kind', 'Repo', 'Aliases', 'Branch', 'Color', 'Path', 'Workspace')
        Write-Host ''
    }
}

function Format-WtwDetailedList {
    param([array] $Items)

    $esc = [char]27

    Write-Host ''
    Write-Host '  ╔══════════════════════════════════════════╗' -ForegroundColor DarkGray
    Write-Host '  ║  wtw — Worktree & Workspace Registry     ║' -ForegroundColor DarkGray
    Write-Host '  ╚══════════════════════════════════════════╝' -ForegroundColor DarkGray
    Write-Host ''

    foreach ($item in $Items) {
        $color = $item.Color
        $isRepo = $item.Kind -eq 'repo'

        if ($isRepo) {
            # Repo header with color swatch
            $swatch = ''
            if ($color -match '^#[0-9a-fA-F]{6}$') {
                $r = [convert]::ToInt32($color.Substring(1, 2), 16)
                $g = [convert]::ToInt32($color.Substring(3, 2), 16)
                $b = [convert]::ToInt32($color.Substring(5, 2), 16)
                $fg = Get-ContrastForeground $color
                $fr = [convert]::ToInt32($fg.Substring(1, 2), 16)
                $fg2 = [convert]::ToInt32($fg.Substring(3, 2), 16)
                $fb = [convert]::ToInt32($fg.Substring(5, 2), 16)
                $swatch = "${esc}[38;2;${fr};${fg2};${fb}m${esc}[48;2;${r};${g};${b}m  $($item.Repo)  ${esc}[0m"
            } else {
                $swatch = "  $($item.Repo)"
            }
            Write-Host "  $swatch" -NoNewline
            Write-Host "  $($item.Branch)" -ForegroundColor Yellow
            Write-Host "    Aliases   : $($item.Aliases)" -ForegroundColor Gray
            Write-Host "    Path      : ${esc}]8;;file://$($item.Path)${esc}\$($item.Path)${esc}]8;;${esc}\" -ForegroundColor Gray
            Write-Host "    Workspace : $($item.Workspace)" -ForegroundColor Gray
            Write-Host ''
        } else {
            # Worktree entry (indented)
            $swatch = ''
            if ($color -match '^#[0-9a-fA-F]{6}$') {
                $r = [convert]::ToInt32($color.Substring(1, 2), 16)
                $g = [convert]::ToInt32($color.Substring(3, 2), 16)
                $b = [convert]::ToInt32($color.Substring(5, 2), 16)
                $swatch = "${esc}[48;2;${r};${g};${b}m  ${esc}[0m"
            } else {
                $swatch = '  '
            }
            Write-Host "    ${swatch} " -NoNewline
            Write-Host "$($item.Branch)" -ForegroundColor Yellow
            Write-Host "      Aliases   : $($item.Aliases)" -ForegroundColor DarkGray
            Write-Host "      Path      : ${esc}]8;;file://$($item.Path)${esc}\$($item.Path)${esc}]8;;${esc}\" -ForegroundColor DarkGray
            Write-Host "      Workspace : $($item.Workspace)" -ForegroundColor DarkGray
            Write-Host ''
        }
    }

    # Settings file links
    $wtwDir = Join-Path $HOME '.wtw'
    $registryFile = Join-Path $wtwDir 'registry.json'
    $colorsFile = Join-Path $wtwDir 'colors.json'
    $configFile = Join-Path $wtwDir 'config.json'

    Write-Host '  ─── Settings ───' -ForegroundColor DarkGray
    if (Test-Path $registryFile) {
        Write-Host "    Registry : ${esc}]8;;file://${registryFile}${esc}\${registryFile}${esc}]8;;${esc}\"  -ForegroundColor DarkCyan
    }
    if (Test-Path $colorsFile) {
        Write-Host "    Colors   : ${esc}]8;;file://${colorsFile}${esc}\${colorsFile}${esc}]8;;${esc}\" -ForegroundColor DarkCyan
    }
    if (Test-Path $configFile) {
        Write-Host "    Config   : ${esc}]8;;file://${configFile}${esc}\${configFile}${esc}]8;;${esc}\" -ForegroundColor DarkCyan
    }
    Write-Host ''
}
