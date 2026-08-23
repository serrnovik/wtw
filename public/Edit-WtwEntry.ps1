function Edit-WtwEntry {
    <#
    .SYNOPSIS
        Edit a registered repo or worktree (name, task key, aliases).
    .DESCRIPTION
        Updates the wtw registry record in place. Does not move git worktrees,
        rename branches, or delete files.

        Worktree:
          --name / second positional   display (pretty) name
          --task                       registry key used by ``wtw go`` and aliases

        Repo:
          --alias / --name / second positional   replace the alias list
          --key                                  registry key (also remaps color keys)

        With no edit flags, prints the current record (cwd when name is omitted).
    .PARAMETER Name
        Repo alias, worktree, or alias-task (same resolution as go/info).
    .PARAMETER NewName
        Shorthand for --name: pretty name (worktree) or alias list (repo).
    .PARAMETER PrettyName
        Display name. A color-circle emoji is prepended for worktrees.
    .PARAMETER Task
        New worktree registry key. Does not rename the folder or branch.
    .PARAMETER Alias
        Comma-separated repo aliases (replaces the existing list).
    .PARAMETER Key
        New repo registry key.
    .PARAMETER Repo
        Disambiguate when the same task exists in multiple repos.
    .PARAMETER NoSync
        Skip rewriting the workspace file and SourceGit bookmark.
    .EXAMPLE
        wtw edit auth --name "Login flow"
        Change the worktree display name shown in list/info and editor sidebars.
    .EXAMPLE
        wtw rename auth login
        Same as ``wtw edit auth --name login``.
    .EXAMPLE
        wtw edit auth --task login
        Retarget ``wtw go login`` / ``sn-login`` without moving the checkout.
    .EXAMPLE
        wtw edit snowmain1 --alias sn,sm
        Replace the repo's typed aliases.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Name,

        [Parameter(Position = 1)]
        [string] $NewName,

        [string[]] $PrettyName,
        [string] $Task,
        [string[]] $Alias,
        [string] $Key,
        [string] $Repo,

        [Alias('ns')]
        [switch] $NoSync
    )

    if (-not $PrettyName -and $NewName) { $PrettyName = @($NewName) }

    $nameFromCwd = -not $Name
    if (-not $Name) {
        $Name = Resolve-WtwCurrentTarget
        if (-not $Name) {
            Write-Error "Not inside a registered repo. Specify a target or cd into a repo."
            return
        }
        if ($nameFromCwd) { Write-Host "  Detected: $Name" -ForegroundColor DarkGray }
    }

    $target = if ($Repo) { Resolve-WtwTarget -Name $Name -RepoAlias $Repo } else { Resolve-WtwTarget $Name }
    if (-not $target) { return }

    $prettyText = Get-WtwJoinedEditValue -Value $PrettyName
    $hasPretty = -not [string]::IsNullOrWhiteSpace($prettyText)
    $hasTask = -not [string]::IsNullOrWhiteSpace($Task)
    $hasAlias = @($Alias | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0
    $hasKey = -not [string]::IsNullOrWhiteSpace($Key)
    $hasEdits = $hasPretty -or $hasTask -or $hasAlias -or $hasKey

    if (-not $hasEdits) {
        Show-WtwEditableRecord -Target $target
        return
    }

    if ($target.TaskName) {
        if ($hasAlias) {
            Write-Error "--alias is for repos. To change how you type this worktree, use --task."
            return
        }
        if ($hasKey) {
            Write-Error "--key is for repos. To rename this worktree's registry key, use --task."
            return
        }
        Edit-WtwWorktreeRecord `
            -Target $target `
            -PrettyName $prettyText `
            -Task $Task `
            -NoSync:$NoSync
        return
    }

    if ($hasTask) {
        Write-Error "--task is for worktrees. To rename this repo's registry key, use --key."
        return
    }

    $aliasInput = if ($hasAlias) { $Alias } elseif ($hasPretty) { $PrettyName } else { $null }
    Edit-WtwRepoRecord `
        -Target $target `
        -Alias $aliasInput `
        -Key $Key `
        -NoSync:$NoSync
}

function Get-WtwJoinedEditValue {
    param([AllowNull()] [string[]] $Value)
    if (-not $Value) { return $null }
    $joined = (@($Value | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join ' ')
    if ([string]::IsNullOrWhiteSpace($joined)) { return $null }
    return $joined
}

function Show-WtwEditableRecord {
    param([Parameter(Mandatory)] [PSObject] $Target)

    $repoName = $Target.RepoName
    $repoEntry = $Target.RepoEntry
    $aliases = Get-WtwRepoAliases $repoEntry

    Write-Host ''
    if ($Target.TaskName) {
        $wt = $Target.WorktreeEntry
        $pretty = Get-WtwPropertyValue -Object $wt -Name 'prettyName'
        $color = Get-WtwPropertyValue -Object $wt -Name 'color'
        $ws = Get-WtwPropertyValue -Object $wt -Name 'workspace'
        $wtAliases = ($aliases | ForEach-Object { "$_-$($Target.TaskName)" }) -join ', '
        Write-Host "  Worktree  $repoName / $($Target.TaskName)" -ForegroundColor Cyan
        if ($pretty) { Write-Host "    Name      : $pretty" }
        Write-Host "    Task      : $($Target.TaskName)"
        Write-Host "    Branch    : $(Get-WtwPropertyValue -Object $wt -Name 'branch')"
        Write-Host "    Path      : $(Get-WtwPropertyValue -Object $wt -Name 'path')"
        if ($ws) { Write-Host "    Workspace : $ws" }
        if ($color) { Write-Host "    Color     : $color" }
        if ($wtAliases) { Write-Host "    Aliases   : $wtAliases" }
        Write-Host ''
        Write-Host "  wtw edit $($Target.TaskName) --name <pretty>   display name" -ForegroundColor DarkGray
        Write-Host "  wtw edit $($Target.TaskName) --task <key>      go-target / aliases" -ForegroundColor DarkGray
    } else {
        Write-Host "  Repo  $repoName" -ForegroundColor Cyan
        Write-Host "    Key       : $repoName"
        Write-Host "    Aliases   : $($aliases -join ', ')"
        Write-Host "    Path      : $(Get-WtwPropertyValue -Object $repoEntry -Name 'mainPath')"
        Write-Host ''
        Write-Host "  wtw edit $repoName --alias a,b     typed names for wtw go" -ForegroundColor DarkGray
        Write-Host "  wtw edit $repoName --key <name>    registry key" -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Edit-WtwWorktreeRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSObject] $Target,
        [string] $PrettyName,
        [string] $Task,
        [switch] $NoSync
    )

    $repoName = $Target.RepoName
    $oldTask = $Target.TaskName
    $newTask = $oldTask
    if (-not [string]::IsNullOrWhiteSpace($Task)) {
        $newTask = ConvertTo-WtwBranchSafeName -Name $Task
        if ([string]::IsNullOrWhiteSpace($newTask)) {
            Write-Error "Invalid --task '$Task'."
            return
        }
        if ($newTask -ne $Task) {
            Write-Host "  Normalized task: $newTask" -ForegroundColor DarkCyan
        }
    }

    $registry = Get-WtwRegistry
    $worktrees = $registry.repos.$repoName.worktrees
    if (-not $worktrees -or ((Get-WtwPropertyNames -Object $worktrees) -notcontains $oldTask)) {
        Write-Error "Worktree '$oldTask' is not in the registry."
        return
    }

    if ($newTask -ne $oldTask -and ((Get-WtwPropertyNames -Object $worktrees) -contains $newTask)) {
        Write-Error "Worktree '$newTask' is already registered under '$repoName'."
        return
    }

    $entry = $worktrees.$oldTask
    $color = Get-WtwPropertyValue -Object $entry -Name 'color'
    $changed = @()

    if (-not [string]::IsNullOrWhiteSpace($PrettyName)) {
        $newPretty = if ($color) {
            Format-WtwPrettyNameWithCircle -Hex $color -Name $PrettyName
        } else {
            $PrettyName.Trim()
        }
        $oldPretty = Get-WtwPropertyValue -Object $entry -Name 'prettyName'
        if ($newPretty -ne $oldPretty) {
            $entry | Add-Member -NotePropertyName 'prettyName' -NotePropertyValue $newPretty -Force
            $changed += "name '$oldPretty' → '$newPretty'"
        }
    }

    if ($newTask -ne $oldTask) {
        $worktrees = Rename-WtwObjectProperty -Object $worktrees -OldName $oldTask -NewName $newTask
        $registry.repos.$repoName.worktrees = $worktrees
        Rename-WtwColorAssignmentKey -OldKey "$repoName/$oldTask" -NewKey "$repoName/$newTask"
        $changed += "task '$oldTask' → '$newTask'"
    } else {
        $registry.repos.$repoName.worktrees.$oldTask = $entry
    }

    if ($changed.Count -eq 0) {
        Write-Host '  Nothing to change.' -ForegroundColor DarkGray
        return
    }

    Save-WtwRegistry $registry

    $saved = $registry.repos.$repoName.worktrees.$newTask
    $prettyNow = Get-WtwPropertyValue -Object $saved -Name 'prettyName'
    $wsFile = Get-WtwPropertyValue -Object $saved -Name 'workspace'
    $wtPath = Get-WtwPropertyValue -Object $saved -Name 'path'

    if (-not $NoSync) {
        if ($wsFile -and (Test-Path $wsFile)) {
            Update-WtwWorkspaceIdentity `
                -Path $wsFile `
                -PrettyName $prettyNow `
                -TaskName $newTask

            if ($prettyNow) {
                $newWsPath = Get-WtwCursorPrettyWorkspacePath -WorkspacePath $wsFile -PrettyName $prettyNow -RepoName $repoName
                $newWsPath = [System.IO.Path]::GetFullPath($newWsPath)
                $oldWsPath = [System.IO.Path]::GetFullPath($wsFile)
                if ($newWsPath -ne $oldWsPath) {
                    $canMigrate = Resolve-WtwCursorStateConflict -PrettyName $prettyNow
                    if ($canMigrate) {
                        $migratedWorkspace = Move-WtwCursorWorkspaceForAgents `
                            -WorkspacePath $wsFile `
                            -PrettyName $prettyNow `
                            -RepoName $repoName
                        if ($migratedWorkspace -and $migratedWorkspace -ne $wsFile) {
                            $saved | Add-Member -NotePropertyName 'workspace' -NotePropertyValue $migratedWorkspace -Force
                            $registry.repos.$repoName.worktrees.$newTask = $saved
                            Save-WtwRegistry $registry
                            $wsFile = $migratedWorkspace
                            Write-Host "  Workspace file: $(Split-Path $wsFile -Leaf)" -ForegroundColor DarkGray
                        }
                    } else {
                        Write-Host '  Keeping existing workspace filename (Cursor Agents label not migrated).' -ForegroundColor DarkGray
                    }
                }
            }

            Write-Host '  Syncing workspace...' -ForegroundColor DarkGray
            Sync-WtwWorkspace -Target $wsFile -ColorSource Json
        }

        if ($wtPath -and $prettyNow) {
            Add-WtwSourceGitRepository -Path $wtPath -Name $prettyNow -Hex $color
        }
    }

    Write-Host ''
    Write-Host "  Updated $repoName / $newTask ($($changed -join '; '))." -ForegroundColor Green
    Write-Host ''
}

function Edit-WtwRepoRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSObject] $Target,
        [string[]] $Alias,
        [string] $Key,
        [switch] $NoSync
    )

    $oldKey = $Target.RepoName
    $newKey = $oldKey
    $workspacesToUpdate = @()
    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        $newKey = $Key.Trim()
        if ([string]::IsNullOrWhiteSpace($newKey)) {
            Write-Error "Invalid --key '$Key'."
            return
        }
    }

    $registry = Get-WtwRegistry
    if ((Get-WtwPropertyNames -Object $registry.repos) -notcontains $oldKey) {
        Write-Error "Repo '$oldKey' is not in the registry."
        return
    }

    $entry = $registry.repos.$oldKey
    $changed = @()

    if (@($Alias | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        # Split-WtwAliasList returns `,@(...)` so a naive `@()` wrap nests it.
        [string[]] $aliasArray = Split-WtwAliasList -Value $Alias
        if ($aliasArray.Count -eq 0) {
            Write-Error "Invalid --alias '$($Alias -join ',')'."
            return
        }
        $collision = Test-WtwRepoIdentityCollision -Registry $registry -RepoName $oldKey -NewKey $oldKey -Aliases $aliasArray
        if ($collision) { return }

        $oldAliases = Get-WtwRepoAliases $entry
        $entry | Add-Member -NotePropertyName 'aliases' -NotePropertyValue $aliasArray -Force
        if ((Get-WtwPropertyNames -Object $entry) -contains 'alias') {
            $entry.PSObject.Properties.Remove('alias')
        }
        $changed += "aliases '$($oldAliases -join ',')' → '$($aliasArray -join ',')'"
    }

    if ($newKey -ne $oldKey) {
        if ((Get-WtwPropertyNames -Object $registry.repos) -contains $newKey) {
            Write-Error "Repo '$newKey' is already in the registry."
            return
        }
        $aliasesForCheck = if (@($Alias | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
            [string[]](Split-WtwAliasList -Value $Alias)
        } else {
            Get-WtwRepoAliases $entry
        }
        $collision = Test-WtwRepoIdentityCollision -Registry $registry -RepoName $oldKey -NewKey $newKey -Aliases $aliasesForCheck
        if ($collision) { return }

        $workspacesToUpdate = @()
        if ($entry.worktrees) {
            foreach ($task in (Get-WtwPropertyNames -Object $entry.worktrees)) {
                $ws = Get-WtwPropertyValue -Object $entry.worktrees.$task -Name 'workspace'
                if ($ws -and (Test-Path $ws)) { $workspacesToUpdate += $ws }
            }
        }
        if (-not $NoSync) {
            foreach ($ws in $workspacesToUpdate) {
                if (-not (Update-WtwWorkspaceIdentity -Path $ws -RepoName $newKey)) {
                    Write-Error "Could not update workspace '$ws' with repo key '$newKey'. Registry was not saved."
                    return
                }
            }
        }

        $registry.repos.$oldKey = $entry
        $registry.repos = Rename-WtwObjectProperty -Object $registry.repos -OldName $oldKey -NewName $newKey
        Rename-WtwColorAssignmentRepoPrefix -OldRepo $oldKey -NewRepo $newKey
        $changed += "key '$oldKey' → '$newKey'"
    } else {
        $registry.repos.$oldKey = $entry
    }

    if ($changed.Count -eq 0) {
        Write-Host '  Nothing to change.' -ForegroundColor DarkGray
        return
    }

    Save-WtwRegistry $registry

    if ($newKey -ne $oldKey -and -not $NoSync) {
        foreach ($ws in @($workspacesToUpdate)) {
            Write-Host '  Syncing workspace...' -ForegroundColor DarkGray
            Sync-WtwWorkspace -Target $ws -ColorSource Json
        }
    }

    Write-Host ''
    Write-Host "  Updated repo $newKey ($($changed -join '; '))." -ForegroundColor Green
    Write-Host "  New shell aliases apply in a new terminal, or re-source the wtw wrapper." -ForegroundColor DarkGray
    Write-Host ''
}

function Test-WtwRepoIdentityCollision {
    <#
    .SYNOPSIS
        Return $true (and write the error) when a proposed repo key/aliases collide.
    #>
    param(
        [Parameter(Mandatory)] [PSObject] $Registry,
        [Parameter(Mandatory)] [string] $RepoName,
        [Parameter(Mandatory)] [string] $NewKey,
        [AllowEmptyCollection()] [string[]] $Aliases
    )

    foreach ($existingName in (Get-WtwPropertyNames -Object $Registry.repos)) {
        if ($existingName -eq $RepoName) { continue }
        $existingRepo = $Registry.repos.$existingName
        $existingAliases = Get-WtwRepoAliases $existingRepo
        foreach ($newAlias in @($Aliases)) {
            if ($newAlias -eq $existingName -or $newAlias -in $existingAliases) {
                Write-Error "Alias '$newAlias' is already used by repo '$existingName'."
                return $true
            }
        }
        if ($NewKey -eq $existingName -or $NewKey -in $existingAliases) {
            Write-Error "Registry key '$NewKey' collides with repo '$existingName'."
            return $true
        }
    }
    return $false
}

function Update-WtwWorkspaceIdentity {
    <#
    .SYNOPSIS
        Write pretty-name / task metadata into an existing workspace file.
    .DESCRIPTION
        Runs before Sync-WtwWorkspace so a single-file sync (which reads
        identity from the file, not the registry) picks up the new values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $PrettyName,
        [string] $TaskName,
        [string] $RepoName
    )

    $workspace = Read-JsoncFile $Path
    if (-not $workspace) { return $false }
    $settings = Get-WtwPropertyValue -Object $workspace -Name 'settings'
    if (-not $settings) { return $false }

    if (-not [string]::IsNullOrWhiteSpace($PrettyName)) {
        $settings | Add-Member -NotePropertyName 'wtw.prettyName' -NotePropertyValue $PrettyName -Force
        $windowTitle = '{0}${{separator}}${{dirty}}${{activeEditorShort}}${{separator}}${{appName}}' -f $PrettyName
        $settings | Add-Member -NotePropertyName 'window.title' -NotePropertyValue $windowTitle -Force
    }
    if (-not [string]::IsNullOrWhiteSpace($TaskName)) {
        $settings | Add-Member -NotePropertyName 'wtw.task' -NotePropertyValue $TaskName -Force
    }
    if (-not [string]::IsNullOrWhiteSpace($RepoName)) {
        $settings | Add-Member -NotePropertyName 'wtw.repo' -NotePropertyValue $RepoName -Force
    }
    try {
        $workspace | ConvertTo-Json -Depth 20 | Set-Content -Path $Path -Encoding utf8
        return $true
    } catch {
        Write-Error "Failed to write workspace identity to '$Path': $_"
        return $false
    }
}
