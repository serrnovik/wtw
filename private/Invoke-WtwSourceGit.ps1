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
    # Use Depth 100 so nested SubNodes survive round-trip. Write without BOM to match SourceGit's writer.
    $json = $Preferences | ConvertTo-Json -Depth 100
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
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
        [string] $Hex
    )

    $bookmark = Get-WtwSourceGitBookmark -Hex $Hex

    $prefPath = Get-WtwSourceGitPreferencePath
    if (-not $prefPath) { return }

    $decision = Resolve-WtwSourceGitConflict -OperationLabel "register '$Name'"
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
    $existing = $nodes | Where-Object { $_.Id -eq $id } | Select-Object -First 1
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
        $prefs.RepositoryNodes = @($nodes + $node)
        Save-WtwSourceGitPreferences -Path $prefPath -Preferences $prefs
        Write-Host "  SourceGit: registered '$Name' (bookmark $bookmark)." -ForegroundColor Green
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
    param([Parameter(Mandatory)][string] $Path)

    $prefPath = Get-WtwSourceGitPreferencePath
    if (-not $prefPath) { return }

    $prefs = Read-WtwSourceGitPreferences -Path $prefPath
    if (-not $prefs) { return }

    if (-not ((Get-WtwPropertyNames -Object $prefs) -contains 'RepositoryNodes') -or -not $prefs.RepositoryNodes) { return }

    $id = ConvertTo-WtwSourceGitId -Path $Path
    $nodes = @($prefs.RepositoryNodes)
    $remaining = @($nodes | Where-Object { $_.Id -ne $id })
    if ($remaining.Count -eq $nodes.Count) { return }

    $decision = Resolve-WtwSourceGitConflict -OperationLabel 'drop entry from preference.json'
    if (-not $decision.proceed) { return }

    # Re-read after potentially closing SourceGit so we don't overwrite its on-exit writes
    if ($decision.relaunch) {
        $prefs = Read-WtwSourceGitPreferences -Path $prefPath
        if (-not $prefs) {
            Start-WtwSourceGitApp | Out-Null
            return
        }
        $nodes = @($prefs.RepositoryNodes)
        $remaining = @($nodes | Where-Object { $_.Id -ne $id })
        if ($remaining.Count -eq $nodes.Count) {
            Start-WtwSourceGitApp | Out-Null
            return
        }
    }

    $prefs.RepositoryNodes = $remaining
    Save-WtwSourceGitPreferences -Path $prefPath -Preferences $prefs
    Write-Host '  SourceGit: removed entry.' -ForegroundColor Green

    if ($decision.relaunch) {
        Write-Host '  SourceGit: relaunching...' -ForegroundColor Cyan
        Start-WtwSourceGitApp | Out-Null
    }
}
