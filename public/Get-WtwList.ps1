function Get-WtwList {
    <#
    .SYNOPSIS
        List all registered repos and worktrees.
    .DESCRIPTION
        Displays a table of all repos and their worktrees with ANSI-colored
        swatches. Detailed mode shows a card layout with clickable file links
        and settings file paths.
    .PARAMETER Repo
        Filter the listing to a specific repo by name or alias.
    .PARAMETER Detailed
        Show card-style output with clickable file links and settings paths.
    .PARAMETER Wide
        Table mode: show every alias variant, full paths, and untruncated branches.
        Default table uses abbreviated aliases (one fuzzy target per worktree),
        ~-shortened paths with middle ellipsis, and truncated branch names.
    .EXAMPLE
        wtw list -d
        Show all repos and worktrees in detailed card layout.
    .EXAMPLE
        wtw list --wide
        Full table columns without shortening (legacy-style density).
    #>
    [CmdletBinding()]
    param(
        [string] $Repo,

        [string] $Task,

        [Alias('d')]
        [switch] $Detailed,

        [switch] $Wide
    )

    $registry = Get-WtwRegistry
    $config = Get-WtwConfig
    $gitCommand = Get-WtwGitCommand
    $repoNames = (Get-WtwPropertyNames -Object $registry.repos)

    if (-not $repoNames -or $repoNames.Count -eq 0) {
        Write-Host '  No repos registered. Run "wtw init" inside a repo.' -ForegroundColor Yellow
        return
    }

    # A --repo filter that matches nothing is almost always a typo or a flag
    # written without dashes (`wtw list detailed`). Say so instead of printing an
    # empty table.
    if ($Repo) {
        $known = @($repoNames | Where-Object {
                $_ -eq $Repo -or ($Repo -in (Get-WtwRepoAliases $registry.repos.$_))
            })
        if ($known.Count -eq 0) {
            Write-Host ''
            Write-Host "  No repo matches '$Repo'." -ForegroundColor Yellow
            Write-Host "  Registered: $(($repoNames | Sort-Object) -join ', ')" -ForegroundColor DarkGray
            Write-Host "  Did you mean a flag? Use --detailed / --wide (with dashes)." -ForegroundColor DarkGray
            Write-Host ''
            return
        }
    }

    $items = @()

    foreach ($name in $repoNames) {
        $repoEntry = $registry.repos.$name
        $aliases = Get-WtwRepoAliases $repoEntry
        if ($Repo -and $Repo -notin $aliases -and $name -ne $Repo) { continue }

        $wsFile = $repoEntry.templateWorkspace
        $wsDisplay = if ($wsFile -and (Test-Path $wsFile)) { Split-Path $wsFile -Leaf } else { '-' }
        $agentProfile = Get-WtwAgentCtlProfile -RepoName $name -RepoEntry $repoEntry -Config $config
        $branch = '?'
        if ($gitCommand) {
            $branch = (& $gitCommand -C $repoEntry.mainPath branch --show-current 2>$null) ?? '?'
        }

        $repoDisplay = Format-WtwRepoDisplayName -Name $name -RepoEntry $repoEntry

        # Main entry
        $items += [PSCustomObject]@{
            Kind      = 'repo'
            Repo      = $repoDisplay
            Task      = '-'
            Aliases   = ($aliases -join "`n")
            Branch    = $branch
            Color     = Get-WtwPropertyValue -Object (Get-WtwColors).assignments -Name "$name/main" -DefaultValue '-'
            Path      = $repoEntry.mainPath
            Workspace = $wsDisplay
            Created   = '-'
            AgentProfile = $agentProfile
        }

        # Worktrees
        if ($repoEntry.worktrees) {
            foreach ($taskName in (Get-WtwPropertyNames -Object $repoEntry.worktrees)) {
                if ($Task -and $taskName -ne $Task) { continue }
                $wt = $repoEntry.worktrees.$taskName
                $exists = Test-Path $wt.path
                $wtWsDisplay = if ($wt.workspace -and (Test-Path $wt.workspace)) { Split-Path $wt.workspace -Leaf } else { '-' }
                $customAliases = @(Get-WtwWorktreeAliases $wt)
                $derivedAliases = @($aliases | ForEach-Object { "$_-$taskName" })
                $wtAliases = (@($customAliases + $derivedAliases) | Where-Object { $_ }) -join "`n"
                $pathDisplay = if ($exists) { $wt.path } else { "$($wt.path) (MISSING)" }

                # Created date: from registry, then git fallback
                $createdStr = '-'
                if ($wt.created) {
                    try { $createdStr = ([datetime]$wt.created).ToString('yyyy-MM-dd') } catch {}
                }
                if ($createdStr -eq '-') {
                    if ($gitCommand -and $exists) {
                        $gitDate = & $gitCommand -C $wt.path log --reverse --format='%cs' 2>$null | Select-Object -First 1
                        if ($gitDate) { $createdStr = $gitDate }
                    } elseif ($gitCommand -and $repoEntry.mainPath -and $wt.branch) {
                        $gitDate = & $gitCommand -C $repoEntry.mainPath log --reverse --format='%cs' $wt.branch 2>$null | Select-Object -First 1
                        if ($gitDate) { $createdStr = $gitDate }
                    }
                }

                $items += [PSCustomObject]@{
                    Kind      = 'wt'
                    Repo      = $repoDisplay
                    Task      = $taskName
                    Aliases   = $wtAliases
                    Branch    = $wt.branch
                    Color     = Get-WtwPropertyValue -Object $wt -Name 'color' -DefaultValue '-'
                    Path      = $pathDisplay
                    Workspace = $wtWsDisplay
                    Created   = $createdStr
                    AgentProfile = $agentProfile
                    PrettyName = Get-WtwPropertyValue -Object $wt -Name 'prettyName'
                    SupersetId = Get-WtwPropertyValue -Object $wt -Name 'supersetWorkspaceId'
                }
            }
        }
    }

    if ($Detailed) {
        Format-WtwDetailedList $items
    } else {
        $tableColumns = if ($Wide) {
            @('Kind', 'Repo', 'Task', 'Aliases', 'Branch', 'Color', 'Path', 'Workspace', 'Created')
        } else {
            @('Kind', 'Repo', 'Task', 'Aliases', 'Branch', 'Color', 'Path', 'Created')
        }
        $tableRows = Get-WtwListRowsForTable -FullItems $items -Wide:$Wide
        Write-Host ''
        Format-WtwTable -Items $tableRows -Columns $tableColumns
        if (-not $Wide) {
            Write-Host '  Tip: wtw list --wide  for full aliases, paths, workspace, and branch names.' -ForegroundColor DarkGray
        }
        Write-Host ''
    }
}

function Show-WtwInfo {
    [CmdletBinding()]
    param([string] $Name)

    if (-not $Name) {
        Get-WtwList -Detailed
        return
    }

    $target = & { Resolve-WtwTarget $Name } 6>$null
    if (-not $target) {
        Write-Host "  No repo or worktree found matching '$Name'" -ForegroundColor Yellow
        return
    }

    if ($target.TaskName) {
        Get-WtwList -Repo $target.RepoName -Task $target.TaskName -Detailed
    } else {
        Get-WtwList -Repo $target.RepoName -Detailed
    }
}

function Write-WtwDetailedAliasesBlock {
    param(
        [string] $Indent,
        [string] $Aliases,
        [string] $ForegroundColor = 'Gray'
    )
    $lines = if ([string]::IsNullOrEmpty($Aliases)) {
        @('')
    } else {
        @($Aliases -split "`n", [StringSplitOptions]::None)
    }
    $nonEmptyLines = @($lines | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ })
    if ($nonEmptyLines.Count -eq 0) {
        Write-Host "${Indent}Aliases   : " -ForegroundColor $ForegroundColor
        return
    }
    Write-Host "${Indent}Aliases   : $($nonEmptyLines[0])" -ForegroundColor $ForegroundColor
    for ($aliasLineIndex = 1; $aliasLineIndex -lt $nonEmptyLines.Count; $aliasLineIndex++) {
        Write-Host "${Indent}            $($nonEmptyLines[$aliasLineIndex])" -ForegroundColor $ForegroundColor
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
            if ($color -match '^#[0-9a-fA-F]{6}$') {
                Write-Host " $color" -ForegroundColor DarkGray -NoNewline
            }
            Write-Host "  $($item.Branch)" -ForegroundColor Yellow
            Write-WtwDetailedAliasesBlock -Indent '    ' -Aliases $item.Aliases -ForegroundColor Gray
            Write-Host "    Path      : ${esc}]8;;file://$($item.Path)${esc}\$($item.Path)${esc}]8;;${esc}\" -ForegroundColor Gray
            Write-Host "    Workspace : $($item.Workspace)" -ForegroundColor Gray
            Write-Host "    Agent     : $($item.AgentProfile)" -ForegroundColor Gray
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
            if ($color -match '^#[0-9a-fA-F]{6}$') {
                Write-Host "$color " -ForegroundColor DarkGray -NoNewline
            }
            Write-Host "$($item.Branch)" -ForegroundColor Yellow
            if ($item.PrettyName) {
                Write-Host "      Name      : $($item.PrettyName)" -ForegroundColor DarkGray
            }
            Write-Host "      Task      : $($item.Task)" -ForegroundColor DarkGray
            Write-WtwDetailedAliasesBlock -Indent '      ' -Aliases $item.Aliases -ForegroundColor DarkGray
            Write-Host "      Path      : ${esc}]8;;file://$($item.Path)${esc}\$($item.Path)${esc}]8;;${esc}\" -ForegroundColor DarkGray
            Write-Host "      Workspace : $($item.Workspace)" -ForegroundColor DarkGray
            Write-Host "      Created   : $($item.Created)" -ForegroundColor DarkGray
            if ($item.SupersetId) {
                Write-Host "      Superset  : $($item.SupersetId)" -ForegroundColor DarkGray
            }
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
