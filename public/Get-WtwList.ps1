function Test-WtwListTextMatch {
    param(
        [string] $Needle,
        [string[]] $Candidates
    )

    if ([string]::IsNullOrWhiteSpace($Needle)) { return $true }
    $n = $Needle.Trim()
    foreach ($candidate in @($Candidates)) {
        if ([string]::IsNullOrEmpty($candidate)) { continue }
        if ($candidate.IndexOf($n, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Test-WtwListRepoMatchesFilter {
    param($Item, [string] $Filter)

    $aliasBits = @()
    if ($Item.Aliases) { $aliasBits = @($Item.Aliases -split "`n") }
    return (Test-WtwListTextMatch -Needle $Filter -Candidates (@($Item.RepoName, $Item.Repo) + $aliasBits))
}

function Test-WtwListWorktreeMatchesFilter {
    param($Item, [string] $Filter)

    $aliasBits = @()
    if ($Item.Aliases) { $aliasBits = @($Item.Aliases -split "`n") }
    return (Test-WtwListTextMatch -Needle $Filter -Candidates (@($Item.TaskName, $Item.Task, $Item.PrettyName) + $aliasBits))
}

function Select-WtwListItemsByFilter {
    param(
        [array] $Items,
        [string] $Filter
    )

    if ([string]::IsNullOrWhiteSpace($Filter)) { return @($Items) }

    $repoFieldHit = @{}
    $worktreeHit = @{}
    foreach ($item in @($Items)) {
        if ($item.Kind -eq 'repo') {
            if (Test-WtwListRepoMatchesFilter -Item $item -Filter $Filter) {
                $repoFieldHit[[string]$item.RepoName] = $true
            }
        } elseif (Test-WtwListWorktreeMatchesFilter -Item $item -Filter $Filter) {
            $worktreeHit["$($item.RepoName)/$($item.TaskName)"] = $true
        }
    }

    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @($Items)) {
        $repoName = [string]$item.RepoName
        if ($item.Kind -eq 'repo') {
            if ($repoFieldHit.ContainsKey($repoName) -or ($worktreeHit.Keys | Where-Object { $_ -like "$repoName/*" })) {
                [void]$selected.Add($item)
            }
        } elseif ($repoFieldHit.ContainsKey($repoName) -or $worktreeHit.ContainsKey("$repoName/$($item.TaskName)")) {
            [void]$selected.Add($item)
        }
    }
    return @($selected)
}

function Get-WtwList {
    <#
    .SYNOPSIS
        List all registered repos and worktrees.
    .DESCRIPTION
        Displays a table of all repos and their worktrees with ANSI-colored
        swatches. The compact table composes identity emojis into Repo/Task.
        Detailed mode (`wtw info`) shows a card layout with Emoji as its own
        field, clickable file links, and settings file paths.
    .PARAMETER Repo
        Filter the listing to a specific repo by exact name or alias.
    .PARAMETER Filter
        Case-insensitive substring across repo names, aliases, worktree tasks,
        and pretty names. A matching repo includes all of its worktrees; a
        matching worktree includes its parent repo row. Aliases: ``-f``, ``--filter``.
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
    .EXAMPLE
        wtw list -f kul
        Only kulissa-prefixed repos (and their worktrees), plus any worktree
        whose task or alias contains ``kul``.
    #>
    [CmdletBinding()]
    param(
        [string] $Repo,

        [string] $Task,

        [Alias('f')]
        [string] $Filter,

        [Alias('d')]
        [switch] $Detailed,

        [switch] $Wide
    )

    $registry = Get-WtwRegistry
    $config = Get-WtwConfig
    $gitCommand = Get-WtwGitCommand
    $repoNames = (Get-WtwPropertyNames -Object $registry.repos)

    if (-not $repoNames -or $repoNames.Count -eq 0) {
        Write-WtwHost '  No repos registered. Run "wtw init" inside a repo.' -ForegroundColor Yellow
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
            Write-WtwHost ''
            Write-WtwHost "  No repo matches '$Repo'." -ForegroundColor Yellow
            Write-WtwHost "  Registered: $(($repoNames | Sort-Object) -join ', ')" -ForegroundColor DarkGray
            Write-WtwHost "  Did you mean a flag? Use --detailed / --wide (with dashes)." -ForegroundColor DarkGray
            Write-WtwHost ''
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

        $repoEmoji = Get-WtwRepoEmoji -RepoEntry $repoEntry
        $repoDisplay = Format-WtwRepoDisplayName -Name $name -RepoEntry $repoEntry

        # Main entry
        $items += [PSCustomObject]@{
            Kind      = 'repo'
            Repo      = $repoDisplay
            RepoName  = $name
            Emoji     = if ($repoEmoji) { $repoEmoji } else { '(none)' }
            Task      = '-'
            TaskName  = '-'
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

                $storedPretty = Get-WtwPropertyValue -Object $wt -Name 'prettyName'
                $wtEmoji = Get-WtwWorktreeEmoji -WorktreeEntry $wt -TaskName $taskName -Name $storedPretty
                $taskDisplay = if ($wtEmoji) { "$wtEmoji $taskName" } else { $taskName }

                $items += [PSCustomObject]@{
                    Kind      = 'wt'
                    Repo      = $repoDisplay
                    RepoName  = $name
                    Emoji     = if ($wtEmoji) { $wtEmoji } else { '(none)' }
                    Task      = $taskDisplay
                    TaskName  = $taskName
                    Aliases   = $wtAliases
                    Branch    = $wt.branch
                    Color     = Get-WtwPropertyValue -Object $wt -Name 'color' -DefaultValue '-'
                    Path      = $pathDisplay
                    Workspace = $wtWsDisplay
                    Created   = $createdStr
                    AgentProfile = $agentProfile
                    PrettyName = $storedPretty
                    SupersetId = Get-WtwPropertyValue -Object $wt -Name 'supersetWorkspaceId'
                }
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Filter)) {
        $beforeFilter = @($items).Count
        $items = @(Select-WtwListItemsByFilter -Items $items -Filter $Filter)
        if ($beforeFilter -gt 0 -and $items.Count -eq 0) {
            Write-WtwHost ''
            Write-WtwHost "  No repo or worktree matches '$Filter'." -ForegroundColor Yellow
            Write-WtwHost "  -f / --filter is a substring (wtw list -f kul). Positional list still needs an exact repo." -ForegroundColor DarkGray
            Write-WtwHost ''
            return
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
        Write-WtwHost ''
        Format-WtwTable -Items $tableRows -Columns $tableColumns
        if (-not $Wide) {
            Write-WtwHost '  Tip: wtw list --wide  for full aliases, paths, workspace, and branch names.' -ForegroundColor DarkGray
        }
        Write-WtwHost ''
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
        Write-WtwHost "  No repo or worktree found matching '$Name'" -ForegroundColor Yellow
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
        Write-WtwHost "${Indent}Aliases   : " -ForegroundColor $ForegroundColor
        return
    }
    Write-WtwHost "${Indent}Aliases   : $($nonEmptyLines[0])" -ForegroundColor $ForegroundColor
    for ($aliasLineIndex = 1; $aliasLineIndex -lt $nonEmptyLines.Count; $aliasLineIndex++) {
        Write-WtwHost "${Indent}            $($nonEmptyLines[$aliasLineIndex])" -ForegroundColor $ForegroundColor
    }
}

function Format-WtwDetailedList {
    param([array] $Items)

    $esc = [char]27

    Write-WtwHost ''
    Write-WtwHost '  ╔╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╗' -ForegroundColor DarkGray
    Write-WtwHost '  ║  wtw — Worktree & Workspace Registry     ║' -ForegroundColor DarkGray
    Write-WtwHost '  ╚╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝╝' -ForegroundColor DarkGray
    Write-WtwHost ''

    foreach ($item in $Items) {
        $color = $item.Color
        $isRepo = $item.Kind -eq 'repo'

        if ($isRepo) {
            # Repo header with color swatch
            $repoLabel = if ($item.RepoName) { $item.RepoName } else { $item.Repo }
            $swatch = ''
            if ($color -match '^#[0-9a-fA-F]{6}$') {
                $r = [convert]::ToInt32($color.Substring(1, 2), 16)
                $g = [convert]::ToInt32($color.Substring(3, 2), 16)
                $b = [convert]::ToInt32($color.Substring(5, 2), 16)
                $fg = Get-ContrastForeground $color
                $fr = [convert]::ToInt32($fg.Substring(1, 2), 16)
                $fg2 = [convert]::ToInt32($fg.Substring(3, 2), 16)
                $fb = [convert]::ToInt32($fg.Substring(5, 2), 16)
                $swatch = "${esc}[38;2;${fr};${fg2};${fb}m${esc}[48;2;${r};${g};${b}m  $repoLabel  ${esc}[0m"
            } else {
                $swatch = "  $repoLabel"
            }
            Write-WtwHost "  $swatch" -NoNewline
            if ($color -match '^#[0-9a-fA-F]{6}$') {
                Write-WtwHost " $color" -ForegroundColor DarkGray -NoNewline
            }
            Write-WtwHost "  $($item.Branch)" -ForegroundColor Yellow
            Write-WtwHost "    Emoji     : $($item.Emoji)" -ForegroundColor Gray
            Write-WtwDetailedAliasesBlock -Indent '    ' -Aliases $item.Aliases -ForegroundColor Gray
            Write-WtwHost "    Path      : ${esc}]8;;file://$($item.Path)${esc}\$($item.Path)${esc}]8;;${esc}\" -ForegroundColor Gray
            Write-WtwHost "    Workspace : $($item.Workspace)" -ForegroundColor Gray
            Write-WtwHost "    Agent     : $($item.AgentProfile)" -ForegroundColor Gray
            Write-WtwHost ''
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
            Write-WtwHost "    ${swatch} " -NoNewline
            if ($color -match '^#[0-9a-fA-F]{6}$') {
                Write-WtwHost "$color " -ForegroundColor DarkGray -NoNewline
            }
            Write-WtwHost "$($item.Branch)" -ForegroundColor Yellow
            if ($item.PrettyName) {
                Write-WtwHost "      Name      : $($item.PrettyName)" -ForegroundColor DarkGray
            }
            $taskLabel = if ($item.TaskName -and $item.TaskName -ne '-') { $item.TaskName } else { $item.Task }
            Write-WtwHost "      Task      : $taskLabel" -ForegroundColor DarkGray
            Write-WtwHost "      Emoji     : $($item.Emoji)" -ForegroundColor DarkGray
            Write-WtwDetailedAliasesBlock -Indent '      ' -Aliases $item.Aliases -ForegroundColor DarkGray
            Write-WtwHost "      Path      : ${esc}]8;;file://$($item.Path)${esc}\$($item.Path)${esc}]8;;${esc}\" -ForegroundColor DarkGray
            Write-WtwHost "      Workspace : $($item.Workspace)" -ForegroundColor DarkGray
            Write-WtwHost "      Created   : $($item.Created)" -ForegroundColor DarkGray
            if ($item.SupersetId) {
                Write-WtwHost "      Superset  : $($item.SupersetId)" -ForegroundColor DarkGray
            }
            Write-WtwHost ''
        }
    }

    # Settings file links
    $wtwDir = Join-Path $HOME '.wtw'
    $registryFile = Join-Path $wtwDir 'registry.json'
    $colorsFile = Join-Path $wtwDir 'colors.json'
    $configFile = Join-Path $wtwDir 'config.json'

    Write-WtwHost '  ─── Settings ───' -ForegroundColor DarkGray
    if (Test-Path $registryFile) {
        Write-WtwHost "    Registry : ${esc}]8;;file://${registryFile}${esc}\${registryFile}${esc}]8;;${esc}\"  -ForegroundColor DarkCyan
    }
    if (Test-Path $colorsFile) {
        Write-WtwHost "    Colors   : ${esc}]8;;file://${colorsFile}${esc}\${colorsFile}${esc}]8;;${esc}\" -ForegroundColor DarkCyan
    }
    if (Test-Path $configFile) {
        Write-WtwHost "    Config   : ${esc}]8;;file://${configFile}${esc}\${configFile}${esc}]8;;${esc}\" -ForegroundColor DarkCyan
    }
    Write-WtwHost ''
}
