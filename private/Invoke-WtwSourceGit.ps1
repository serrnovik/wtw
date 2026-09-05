function Get-WtwSourceGitPreferencePath {
    <#
    .SYNOPSIS
        Return SourceGit's preference.json path when SourceGit is installed.
    .DESCRIPTION
        SourceGit (cross-platform) stores its managed repository list in
        <DataDir>/preference.json under the RepositoryNodes array. DataDir per
        platform (mirrors src/Native/{MacOS,Linux,Windows}.cs GetDataDir):
          - macOS:   ~/Library/Application Support/SourceGit
          - Linux:   ~/.sourcegit
          - Windows: %APPDATA%\SourceGit
        Portable installs (Windows exe-dir\data, AppImage-dir\data) aren't
        auto-detected — set WTW_SOURCEGIT_PREF to override. Returns $null when
        the file is missing (treated as "SourceGit not configured here").
    #>
    $override = [Environment]::GetEnvironmentVariable('WTW_SOURCEGIT_PREF')
    if ($override) {
        return $(if (Test-Path $override) { $override } else { $null })
    }

    $path = $null
    if ($IsMacOS) {
        $path = Join-Path $HOME 'Library/Application Support/SourceGit/preference.json'
    } elseif ($IsLinux) {
        $path = Join-Path $HOME '.sourcegit/preference.json'
    } elseif ($IsWindows -or $env:OS -eq 'Windows_NT') {
        $appData = [Environment]::GetFolderPath('ApplicationData')
        $scoopUser = [Environment]::GetEnvironmentVariable('SCOOP')
        if (-not $scoopUser) { $scoopUser = Join-Path $HOME 'scoop' }
        
        $candidates = @()
        if ($appData) { $candidates += Join-Path $appData 'SourceGit/preference.json' }
        $candidates += Join-Path $scoopUser 'persist/sourcegit/data/preference.json'

        foreach ($c in $candidates) {
            if (Test-Path $c) {
                $path = $c
                break
            }
        }
    }

    if (-not $path -or -not (Test-Path $path)) { return $null }
    return $path
}

function Test-WtwSourceGitRunning {
    $proc = Get-Process -Name 'SourceGit' -ErrorAction SilentlyContinue
    return [bool]$proc
}

function Stop-WtwSourceGitProcess {
    <#
    .SYNOPSIS
        Stop SourceGit and wait for it to exit. Returns $true on success.
    #>
    param([int] $TimeoutSeconds = 10)

    $procs = @(Get-Process -Name 'SourceGit' -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return $true }

    foreach ($p in $procs) {
        try { $p.CloseMainWindow() | Out-Null } catch { }
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-WtwSourceGitRunning)) { return $true }
        Start-Sleep -Milliseconds 250
    }

    # Still running — escalate to Kill
    foreach ($p in @(Get-Process -Name 'SourceGit' -ErrorAction SilentlyContinue)) {
        try { $p.Kill($true) } catch { try { $p.Kill() } catch { } }
    }
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-WtwSourceGitRunning)) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return -not (Test-WtwSourceGitRunning)
}

function Start-WtwSourceGitApp {
    <#
    .SYNOPSIS
        Relaunch SourceGit on the current platform. Best-effort.
    #>
    param([string] $OpenPath)

    try {
        if ($IsMacOS) {
            $bin = '/Applications/SourceGit.app/Contents/MacOS/SourceGit'
            if (Test-Path $bin) {
                # Invoke binary directly so argv reaches SourceGit's IPC handler; `open -a` drops the path
                # (Apple file-open event) and `open -n --args` is suppressed by single-instance lock.
                if ($OpenPath) { Start-Process -FilePath $bin -ArgumentList $OpenPath }
                else           { Start-Process -FilePath $bin }
                return $true
            }
        } elseif ($IsLinux) {
            $cmd = Get-Command sourcegit -ErrorAction SilentlyContinue
            if ($cmd) {
                if ($OpenPath) { Start-Process -FilePath $cmd.Source -ArgumentList $OpenPath } else { Start-Process -FilePath $cmd.Source }
                return $true
            }
        } elseif ($IsWindows -or $env:OS -eq 'Windows_NT') {
            $candidates = @(
                (Join-Path ${env:LOCALAPPDATA} 'SourceGit/SourceGit.exe'),
                (Join-Path ${env:ProgramFiles} 'SourceGit/SourceGit.exe')
            ) | Where-Object { $_ -and (Test-Path $_) }
            $exe = $candidates | Select-Object -First 1
            if (-not $exe) {
                $cmd = Get-Command SourceGit -ErrorAction SilentlyContinue
                if ($cmd) { $exe = $cmd.Source }
            }
            if ($exe) {
                if ($OpenPath) { Start-Process -FilePath $exe -ArgumentList $OpenPath } else { Start-Process -FilePath $exe }
                return $true
            }
        }
    } catch { }
    return $false
}

function Resolve-WtwSourceGitConflict {
    <#
    .SYNOPSIS
        When SourceGit is running, ask the user how to proceed before modifying
        preference.json. Caller must relaunch after the write if 'relaunch' is true.
    .OUTPUTS
        Hashtable @{ proceed=$bool; relaunch=$bool } — proceed=false means skip the write.
    #>
    param([string] $OperationLabel = 'update preference.json')

    if (-not (Test-WtwSourceGitRunning)) { return @{ proceed = $true; relaunch = $false } }

    Write-Host ''
    Write-Host '  SourceGit is running — it overwrites preference.json on exit.' -ForegroundColor Yellow
    Write-Host "  How should I $OperationLabel"'?' -ForegroundColor Yellow
    Write-Host '    [c] Close SourceGit, then write (I will wait, then relaunch)'
    Write-Host '    [k] Force-kill SourceGit, write, relaunch'
    Write-Host '    [i] Ignore — write anyway (you restart SourceGit later)'
    Write-Host '    [s] Skip — do not modify preference.json'

    $answer = (Read-Host '  Choice [c/k/i/s]').Trim().ToLowerInvariant()
    if (-not $answer) { $answer = 'c' }

    switch ($answer) {
        'c' {
            Write-Host '  Waiting for SourceGit to close (Ctrl+C to abort)...' -ForegroundColor Cyan
            while (Test-WtwSourceGitRunning) { Start-Sleep -Milliseconds 500 }
            Write-Host '  SourceGit closed.' -ForegroundColor Green
            return @{ proceed = $true; relaunch = $true }
        }
        'k' {
            Write-Host '  Force-closing SourceGit...' -ForegroundColor Cyan
            if (-not (Stop-WtwSourceGitProcess)) {
                Write-Host '  Could not stop SourceGit — skipping write.' -ForegroundColor Red
                return @{ proceed = $false; relaunch = $false }
            }
            Write-Host '  SourceGit stopped.' -ForegroundColor Green
            return @{ proceed = $true; relaunch = $true }
        }
        's' {
            Write-Host '  Skipped SourceGit update.' -ForegroundColor DarkGray
            return @{ proceed = $false; relaunch = $false }
        }
        default {
            # 'i' or anything else → write while running; user restarts later
            Write-Host '  Writing anyway — restart SourceGit to pick up the change.' -ForegroundColor Yellow
            return @{ proceed = $true; relaunch = $false }
        }
    }
}

function ConvertTo-WtwSourceGitId {
    param([string] $Path)
    # Mirror SourceGit's RepositoryNode.Id setter: backslash → forward slash, trim trailing /
    $normalized = $Path.Replace('\', '/')
    $normalized = $normalized.TrimEnd('/')
    return $normalized
}

function Read-WtwSourceGitPreferences {
    param([string] $Path)
    try {
        $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
        return ($raw | ConvertFrom-Json -Depth 100 -ErrorAction Stop)
    } catch {
        Write-Host "  SourceGit: could not parse preference.json — skipping ($($_.Exception.Message))" -ForegroundColor Yellow
        return $null
    }
}

function Save-WtwSourceGitPreferences {
    param(
        [string] $Path,
        [psobject] $Preferences
    )
    Backup-WtwExternalConfig -System 'sourcegit' -Path $Path | Out-Null
    # Use Depth 100 so nested SubNodes survive round-trip. Write without BOM to match SourceGit's writer.
    $json = $Preferences | ConvertTo-Json -Depth 100
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Get-WtwSourceGitWriteDecision {
    param(
        [string] $OperationLabel,
        [switch] $Force
    )
    if ($Force -or $script:WtwSourceGitForce -eq $true -or $env:WTW_SOURCEGIT_FORCE -eq '1') {
        return @{ proceed = $true; relaunch = $false }
    }
    return Resolve-WtwSourceGitConflict -OperationLabel $OperationLabel
}

function Find-WtwSourceGitNode {
    <#
    .SYNOPSIS
        Find a RepositoryNode by Id, including nested SubNodes.
    #>
    param(
        $Nodes,
        [Parameter(Mandatory)]
        [string] $Id
    )

    foreach ($node in @($Nodes)) {
        if ($null -eq $node) { continue }
        if ((Get-WtwPropertyValue -Object $node -Name 'Id') -eq $Id) { return $node }
        $sub = Get-WtwPropertyValue -Object $node -Name 'SubNodes'
        if ($sub) {
            $found = Find-WtwSourceGitNode -Nodes @($sub) -Id $Id
            if ($found) { return $found }
        }
    }
    return $null
}

function Remove-WtwSourceGitNodeById {
    <#
    .SYNOPSIS
        Drop a RepositoryNode by Id from a tree, including nested SubNodes.
    #>
    param(
        [AllowNull()]
        [object[]] $Nodes,

        [Parameter(Mandatory)]
        [string] $Id
    )

    $kept = [System.Collections.Generic.List[object]]::new()
    $removed = $false
    foreach ($node in @($Nodes)) {
        if ($null -eq $node) { continue }
        if ((Get-WtwPropertyValue -Object $node -Name 'Id') -eq $Id) {
            $removed = $true
            continue
        }
        $sub = @(Get-WtwPropertyValue -Object $node -Name 'SubNodes')
        if ($sub.Count -gt 0 -and $null -ne $sub[0]) {
            $result = Remove-WtwSourceGitNodeById -Nodes $sub -Id $Id
            $node | Add-Member -NotePropertyName 'SubNodes' -NotePropertyValue @($result.Nodes) -Force
            if ($result.Removed) { $removed = $true }
        }
        $kept.Add($node)
    }
    return [PSCustomObject]@{
        Nodes   = @($kept.ToArray())
        Removed = $removed
    }
}

function Update-WtwSourceGitNodeNames {
    <#
    .SYNOPSIS
        Rename matching SourceGit nodes (by Id and/or current Name).
    #>
    param(
        $Nodes,
        [string[]] $MatchIds,
        [string[]] $MatchNames,
        [Parameter(Mandatory)]
        [string] $NewName
    )

    $idSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($id in @($MatchIds)) {
        if ($id) { [void]$idSet.Add($id) }
    }
    $nameSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($name in @($MatchNames)) {
        if ($name) { [void]$nameSet.Add($name) }
    }

    $changed = $false
    foreach ($node in @($Nodes)) {
        if ($null -eq $node) { continue }
        $id = Get-WtwPropertyValue -Object $node -Name 'Id'
        $name = Get-WtwPropertyValue -Object $node -Name 'Name'
        $matches = ($id -and $idSet.Contains([string]$id)) -or ($name -and $nameSet.Contains([string]$name))
        if ($matches -and $name -ne $NewName) {
            $node.Name = $NewName
            $changed = $true
        }
        $sub = Get-WtwPropertyValue -Object $node -Name 'SubNodes'
        if ($sub) {
            if (Update-WtwSourceGitNodeNames -Nodes @($sub) -MatchIds $MatchIds -MatchNames $MatchNames -NewName $NewName) {
                $changed = $true
            }
        }
    }
    return $changed
}

function Add-WtwSourceGitRepository {
    <#
    .SYNOPSIS
        Register a worktree in SourceGit's managed repository list (macOS only).
    .DESCRIPTION
        Appends or updates a RepositoryNode entry pointing at the worktree path.
        Silently no-ops when not on macOS, when SourceGit isn't installed, or
        when the preference file is missing. Warns when SourceGit is running
        because it overwrites preference.json on exit.
    #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Name,
        [string] $Hex,
        [string] $RepoName,
        [switch] $Force
    )

    $bookmark = Get-WtwSourceGitBookmark -Hex $Hex

    $prefPath = Get-WtwSourceGitPreferencePath
    if (-not $prefPath) { return }

    $decision = Get-WtwSourceGitWriteDecision -OperationLabel "register '$Name'" -Force:$Force
    if (-not $decision.proceed) { return }

    $prefs = Read-WtwSourceGitPreferences -Path $prefPath
    if (-not $prefs) {
        if ($decision.relaunch) { Start-WtwSourceGitApp -OpenPath $Path | Out-Null }
        return
    }

    if (-not ((Get-WtwPropertyNames -Object $prefs) -contains 'RepositoryNodes') -or -not $prefs.RepositoryNodes) {
        $prefs | Add-Member -NotePropertyName 'RepositoryNodes' -NotePropertyValue @() -Force
    }

    $id = ConvertTo-WtwSourceGitId -Path $Path

    $nodes = @($prefs.RepositoryNodes)
    $existing = Find-WtwSourceGitNode -Nodes $nodes -Id $id
    if ($existing) {
        $existing.Name = $Name
        $existing.IsRepository = $true
        if ($bookmark -gt 0) { $existing.Bookmark = $bookmark }
        $prefs.RepositoryNodes = $nodes
        Save-WtwSourceGitPreferences -Path $prefPath -Preferences $prefs
        Write-Host "  SourceGit: updated entry '$Name' (bookmark $($existing.Bookmark))." -ForegroundColor Green
    } else {
        $node = [PSCustomObject]@{
            Id           = $id
            Name         = $Name
            Bookmark     = $bookmark
            IsRepository = $true
            IsExpanded   = $false
            Status       = $null
            SubNodes     = @()
        }
        $owner = Resolve-WtwSourceGitRepoOwner -Path $Path -RepoName $RepoName
        $placed = $false
        if ($owner) {
            $skipNest = $false
            if ((Get-WtwPropertyNames -Object $owner.Entry) -contains 'sourceGitFolder') {
                $skipNest = ($owner.Entry.sourceGitFolder -eq $false)
            }
            $folder = Find-WtwSourceGitRepoFolder -Nodes $nodes -RepoName $owner.Name -RepoEntry $owner.Entry
            if ($folder) {
                $subs = @(Get-WtwPropertyValue -Object $folder -Name 'SubNodes')
                $folder | Add-Member -NotePropertyName 'SubNodes' -NotePropertyValue @($subs + $node) -Force
                $prefs.RepositoryNodes = $nodes
                $placed = $true
                Write-Host "  SourceGit: registered '$Name' under folder '$($folder.Name)' (bookmark $bookmark)." -ForegroundColor Green
            } elseif (-not $skipNest -and ((Get-WtwPropertyNames -Object $owner.Entry) -contains 'sourceGitFolder') -and $owner.Entry.sourceGitFolder -eq $true) {
                $folder = New-WtwSourceGitFolderNode -RepoName $owner.Name -RepoEntry $owner.Entry -Bookmark $bookmark
                Move-WtwSourceGitMainIntoFolder -Preferences $prefs -Folder $folder -MainPath $owner.Entry.mainPath
                $subs = @(Get-WtwPropertyValue -Object $folder -Name 'SubNodes')
                $folder | Add-Member -NotePropertyName 'SubNodes' -NotePropertyValue @($subs + $node) -Force
                if (-not (Find-WtwSourceGitNode -Nodes @($prefs.RepositoryNodes) -Id $folder.Id)) {
                    $prefs.RepositoryNodes = @($prefs.RepositoryNodes + $folder)
                }
                $placed = $true
                Write-Host "  SourceGit: created folder '$($folder.Name)' and registered '$Name' (bookmark $bookmark)." -ForegroundColor Green
            }
        }
        if (-not $placed) {
            $prefs.RepositoryNodes = @($nodes + $node)
            Write-Host "  SourceGit: registered '$Name' (bookmark $bookmark)." -ForegroundColor Green
        }
        Save-WtwSourceGitPreferences -Path $prefPath -Preferences $prefs
    }

    if ($decision.relaunch) {
        Write-Host '  SourceGit: relaunching...' -ForegroundColor Cyan
        Start-WtwSourceGitApp -OpenPath $Path | Out-Null
    }
}

function Remove-WtwSourceGitRepository {
    <#
    .SYNOPSIS
        Drop a worktree from SourceGit's managed repository list (macOS only).
    .DESCRIPTION
        Removes any RepositoryNode whose Id matches the given path. Silent no-op
        when not on macOS, when SourceGit is missing, or when no match is found.
    #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [switch] $Force
    )

    $prefPath = Get-WtwSourceGitPreferencePath
    if (-not $prefPath) { return }

    $prefs = Read-WtwSourceGitPreferences -Path $prefPath
    if (-not $prefs) { return }

    if (-not ((Get-WtwPropertyNames -Object $prefs) -contains 'RepositoryNodes') -or -not $prefs.RepositoryNodes) { return }

    $id = ConvertTo-WtwSourceGitId -Path $Path
    $nodes = @($prefs.RepositoryNodes)
    $pruned = Remove-WtwSourceGitNodeById -Nodes $nodes -Id $id
    if (-not $pruned.Removed) { return }

    $decision = Get-WtwSourceGitWriteDecision -OperationLabel 'drop entry from preference.json' -Force:$Force
    if (-not $decision.proceed) { return }

    # Re-read after potentially closing SourceGit so we don't overwrite its on-exit writes
    if ($decision.relaunch) {
        $prefs = Read-WtwSourceGitPreferences -Path $prefPath
        if (-not $prefs) {
            Start-WtwSourceGitApp | Out-Null
            return
        }
        $nodes = @($prefs.RepositoryNodes)
        $pruned = Remove-WtwSourceGitNodeById -Nodes $nodes -Id $id
        if (-not $pruned.Removed) {
            Start-WtwSourceGitApp | Out-Null
            return
        }
    }

    $prefs.RepositoryNodes = @($pruned.Nodes)
    Save-WtwSourceGitPreferences -Path $prefPath -Preferences $prefs
    Write-Host '  SourceGit: removed entry.' -ForegroundColor Green

    if ($decision.relaunch) {
        Write-Host '  SourceGit: relaunching...' -ForegroundColor Cyan
        Start-WtwSourceGitApp | Out-Null
    }
}

function Sync-WtwSourceGitRepoDisplayName {
    <#
    .SYNOPSIS
        Apply a repo's emoji-prefixed display name to SourceGit nodes.
    .DESCRIPTION
        Updates the main-checkout node (by path Id) and any group/node whose
        Name is the registry key or a previous display name. Registers the
        main path if SourceGit has no matching node yet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RepoName,
        [Parameter(Mandatory)] $RepoEntry,
        [string] $PreviousDisplayName,
        [switch] $Force
    )

    $prefPath = Get-WtwSourceGitPreferencePath
    if (-not $prefPath) { return }

    $mainPath = Get-WtwPropertyValue -Object $RepoEntry -Name 'mainPath'
    if (-not $mainPath) { return }

    $display = Format-WtwRepoDisplayName -Name $RepoName -RepoEntry $RepoEntry
    $hex = Get-WtwPropertyValue -Object (Get-WtwColors).assignments -Name "$RepoName/main"
    $id = ConvertTo-WtwSourceGitId -Path $mainPath

    $decision = Get-WtwSourceGitWriteDecision -OperationLabel "rename repo to '$display'" -Force:$Force
    if (-not $decision.proceed) { return }

    if ($decision.relaunch) {
        $prefs = Read-WtwSourceGitPreferences -Path $prefPath
    } else {
        $prefs = Read-WtwSourceGitPreferences -Path $prefPath
    }
    if (-not $prefs) {
        if ($decision.relaunch) { Start-WtwSourceGitApp | Out-Null }
        return
    }

    if (-not ((Get-WtwPropertyNames -Object $prefs) -contains 'RepositoryNodes') -or -not $prefs.RepositoryNodes) {
        Add-WtwSourceGitRepository -Path $mainPath -Name $display -Hex $hex -Force
        if ($decision.relaunch) { Start-WtwSourceGitApp -OpenPath $mainPath | Out-Null }
        return
    }

    $matchNames = @($RepoName, $PreviousDisplayName) | Where-Object { $_ -and $_ -ne $display }
    $changed = Update-WtwSourceGitNodeNames `
        -Nodes @($prefs.RepositoryNodes) `
        -MatchIds @($id, "wtw-folder:$RepoName") `
        -MatchNames $matchNames `
        -NewName $display

    if (-not $changed) {
        if (-not (Find-WtwSourceGitNode -Nodes @($prefs.RepositoryNodes) -Id $id)) {
            Add-WtwSourceGitRepository -Path $mainPath -Name $display -Hex $hex -Force
        }
        if ($decision.relaunch) { Start-WtwSourceGitApp -OpenPath $mainPath | Out-Null }
        return
    }

    Save-WtwSourceGitPreferences -Path $prefPath -Preferences $prefs
    Write-Host "  SourceGit: repo display name is now '$display'." -ForegroundColor Green

    if ($decision.relaunch) {
        Write-Host '  SourceGit: relaunching...' -ForegroundColor Cyan
        Start-WtwSourceGitApp -OpenPath $mainPath | Out-Null
    }
}

function Resolve-WtwSourceGitRepoOwner {
    param(
        [string] $Path,
        [string] $RepoName
    )

    $registry = Get-WtwRegistry
    if (-not $registry -or -not $registry.repos) { return $null }
    if ($RepoName -and ((Get-WtwPropertyNames -Object $registry.repos) -contains $RepoName)) {
        return [PSCustomObject]@{ Name = $RepoName; Entry = $registry.repos.$RepoName }
    }
    if (-not $Path) { return $null }
    $id = ConvertTo-WtwSourceGitId -Path $Path
    foreach ($name in (Get-WtwPropertyNames -Object $registry.repos)) {
        $entry = $registry.repos.$name
        $mainPath = Get-WtwPropertyValue -Object $entry -Name 'mainPath'
        if ($mainPath -and (ConvertTo-WtwSourceGitId -Path $mainPath) -eq $id) {
            return [PSCustomObject]@{ Name = $name; Entry = $entry }
        }
        if (-not $entry.worktrees) { continue }
        foreach ($task in (Get-WtwPropertyNames -Object $entry.worktrees)) {
            $wtPath = Get-WtwPropertyValue -Object $entry.worktrees.$task -Name 'path'
            if ($wtPath -and (ConvertTo-WtwSourceGitId -Path $wtPath) -eq $id) {
                return [PSCustomObject]@{ Name = $name; Entry = $entry }
            }
        }
    }
    return $null
}

function Find-WtwSourceGitRepoFolder {
    param(
        $Nodes,
        [Parameter(Mandatory)] [string] $RepoName,
        $RepoEntry
    )

    $folderId = "wtw-folder:$RepoName"
    $display = if ($RepoEntry) { Format-WtwRepoDisplayName -Name $RepoName -RepoEntry $RepoEntry } else { $RepoName }
    $mainId = $null
    if ($RepoEntry) {
        $mainPath = Get-WtwPropertyValue -Object $RepoEntry -Name 'mainPath'
        if ($mainPath) { $mainId = ConvertTo-WtwSourceGitId -Path $mainPath }
    }
    $displayKey = ConvertTo-WtwLookupKey $display
    $repoKey = ConvertTo-WtwLookupKey $RepoName

    foreach ($node in @($Nodes)) {
        if ($null -eq $node) { continue }
        $id = Get-WtwPropertyValue -Object $node -Name 'Id'
        $isRepo = Get-WtwPropertyValue -Object $node -Name 'IsRepository'
        $name = Get-WtwPropertyValue -Object $node -Name 'Name'
        $isFolder = ($isRepo -eq $false) -or ($id -eq $folderId)
        if ($isFolder) {
            if ($id -eq $folderId) { return $node }
            $nameKey = ConvertTo-WtwLookupKey $name
            if ($nameKey -and ($nameKey -eq $displayKey -or $nameKey -eq $repoKey)) { return $node }
            if ($mainId) {
                $sub = @(Get-WtwPropertyValue -Object $node -Name 'SubNodes')
                if (Find-WtwSourceGitNode -Nodes $sub -Id $mainId) { return $node }
            }
        }
        $nested = Get-WtwPropertyValue -Object $node -Name 'SubNodes'
        if ($nested) {
            $found = Find-WtwSourceGitRepoFolder -Nodes @($nested) -RepoName $RepoName -RepoEntry $RepoEntry
            if ($found) { return $found }
        }
    }
    return $null
}

function New-WtwSourceGitFolderNode {
    param(
        [Parameter(Mandatory)] [string] $RepoName,
        [Parameter(Mandatory)] $RepoEntry,
        [int] $Bookmark = 5
    )

    $display = Format-WtwRepoDisplayName -Name $RepoName -RepoEntry $RepoEntry
    return [PSCustomObject]@{
        Id           = "wtw-folder:$RepoName"
        Name         = $display
        Bookmark     = $Bookmark
        IsRepository = $false
        IsExpanded   = $true
        Status       = $null
        SubNodes     = @()
    }
}

function Move-WtwSourceGitMainIntoFolder {
    param(
        [Parameter(Mandatory)] $Preferences,
        [Parameter(Mandatory)] $Folder,
        [string] $MainPath
    )

    if (-not $MainPath) { return }
    $mainId = ConvertTo-WtwSourceGitId -Path $MainPath
    $already = Find-WtwSourceGitNode -Nodes @(Get-WtwPropertyValue -Object $Folder -Name 'SubNodes') -Id $mainId
    if ($already) { return }
    $main = Find-WtwSourceGitNode -Nodes @($Preferences.RepositoryNodes) -Id $mainId
    if (-not $main) { return }
    $pruned = Remove-WtwSourceGitNodeById -Nodes @($Preferences.RepositoryNodes) -Id $mainId
    $Preferences.RepositoryNodes = @($pruned.Nodes)
    $subs = @(Get-WtwPropertyValue -Object $Folder -Name 'SubNodes')
    $Folder | Add-Member -NotePropertyName 'SubNodes' -NotePropertyValue (@($main) + $subs) -Force
}

function Ensure-WtwSourceGitRepoFolder {
    <#
    .SYNOPSIS
        Create a SourceGit group for a repo and move its main checkout into it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoName,
        [Parameter(Mandatory)] $RepoEntry,
        [switch] $Force
    )

    $prefPath = Get-WtwSourceGitPreferencePath
    if (-not $prefPath) { return }

    $decision = Get-WtwSourceGitWriteDecision -OperationLabel "group '$RepoName' in a folder" -Force:$Force
    if (-not $decision.proceed) { return }

    $prefs = Read-WtwSourceGitPreferences -Path $prefPath
    if (-not $prefs) {
        if ($decision.relaunch) { Start-WtwSourceGitApp | Out-Null }
        return
    }
    if (-not ((Get-WtwPropertyNames -Object $prefs) -contains 'RepositoryNodes') -or -not $prefs.RepositoryNodes) {
        $prefs | Add-Member -NotePropertyName 'RepositoryNodes' -NotePropertyValue @() -Force
    }

    $folder = Find-WtwSourceGitRepoFolder -Nodes @($prefs.RepositoryNodes) -RepoName $RepoName -RepoEntry $RepoEntry
    if (-not $folder) {
        $hex = Get-WtwPropertyValue -Object (Get-WtwColors).assignments -Name "$RepoName/main"
        $bookmark = Get-WtwSourceGitBookmark -Hex $hex
        $folder = New-WtwSourceGitFolderNode -RepoName $RepoName -RepoEntry $RepoEntry -Bookmark $bookmark
        $prefs.RepositoryNodes = @($prefs.RepositoryNodes + $folder)
    }
    Move-WtwSourceGitMainIntoFolder -Preferences $prefs -Folder $folder -MainPath (Get-WtwPropertyValue -Object $RepoEntry -Name 'mainPath')
    Save-WtwSourceGitPreferences -Path $prefPath -Preferences $prefs
    Write-Host "  SourceGit: using folder '$($folder.Name)' for $RepoName." -ForegroundColor Green
    if ($decision.relaunch) {
        Write-Host '  SourceGit: relaunching...' -ForegroundColor Cyan
        Start-WtwSourceGitApp | Out-Null
    }
}
