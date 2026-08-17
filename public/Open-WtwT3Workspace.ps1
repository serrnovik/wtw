function Open-WtwT3Workspace {
    <#
    .SYNOPSIS
        Register a wtw target as a T3 Code project, then bring T3 Code up.
    .DESCRIPTION
        T3 Code 0.0.33 has no CLI and no folder-open deep link, so "open this
        worktree" cannot be handed to a running app the way `wtw code` or
        `wtw cmux` can. What wtw can do is make sure the worktree is already a
        project — under its wtw pretty name — before the app starts, so it is one
        click away in the sidebar.

        Registration writes to T3 Code's event store and therefore only runs
        while the app is stopped. When it is already running, wtw points the
        "Add project starts in" setting at the worktree instead and says so.

        T3 Code's project model has no color field, so `wtw color` does not reach
        this integration — the pretty name is the whole identity.
    .PARAMETER Target
        Resolved wtw target object (output of Resolve-WtwTarget).
    .PARAMETER Editor
        Resolved editor metadata; supplies appNameCandidates when present.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Target,

        [object] $Editor
    )

    $dir = if ($Target.WorktreeEntry) { $Target.WorktreeEntry.path } else { $Target.RepoEntry.mainPath }
    if (-not ($dir -and (Test-Path $dir))) {
        Write-Error 'No directory found for T3 Code target.'
        return
    }

    $fullDir = [System.IO.Path]::GetFullPath($dir)

    $prettyName = Get-WtwPropertyValue -Object $Target.WorktreeEntry -Name 'prettyName'
    if (-not $prettyName) { $prettyName = $Target.TaskName }
    if (-not $prettyName) { $prettyName = Split-Path $fullDir -Leaf }

    $candidates = Get-WtwPropertyValue -Object $Editor -Name 'appNameCandidates' `
        -DefaultValue @('T3 Code', 'T3 Code (Alpha)', 'T3 Code (Beta)')

    $appName = Get-WtwT3MacAppName -Candidates $candidates
    if ($IsMacOS -and -not $appName) {
        $tried = ($candidates | ForEach-Object { "$_.app" }) -join ', '
        Write-Error "T3 Code is not installed. Tried: $tried"
        return
    }

    # Read-only preflight: safe while T3 is running, and it keeps wtw from asking
    # to quit the app on every run of an already-registered worktree.
    $plan = Get-WtwT3RegistrationPlan -ProjectPath $fullDir -PrettyName $prettyName

    if ($plan.Action -eq 'none') {
        Write-Host "  T3 Code: project already '$prettyName'" -ForegroundColor DarkGray
    } elseif ($plan.Action -eq 'blocked') {
        Write-Host "  T3 Code: $($plan.Reason)" -ForegroundColor Yellow
        if (Set-WtwT3AddProjectBaseDirectory -Path $fullDir) {
            Write-Host "  T3 Code: 'Add project' will start in this worktree" -ForegroundColor DarkGray
        }
    } else {
        # Writing needs T3 stopped — its server owns the store while it runs.
        $decision = Resolve-WtwT3StateConflict -Candidates $candidates
        if ($decision.proceed) {
            $result = Register-WtwT3Project -ProjectPath $fullDir -PrettyName $prettyName
            switch ($result.Status) {
                'created'   { Write-Host "  T3 Code: project '$prettyName' added" -ForegroundColor Green }
                'renamed'   { Write-Host "  T3 Code: project renamed to '$prettyName'" -ForegroundColor Green }
                'unchanged' { Write-Host "  T3 Code: project already '$prettyName'" -ForegroundColor DarkGray }
                default     { Write-Host "  T3 Code: $($result.Reason)" -ForegroundColor Yellow }
            }
        } else {
            Write-Host "  T3 Code: left running — '$prettyName' not registered." -ForegroundColor DarkGray
            if (Set-WtwT3AddProjectBaseDirectory -Path $fullDir) {
                Write-Host "  T3 Code: 'Add project' will start in this worktree" -ForegroundColor DarkGray
            }
        }
    }

    # 0.0.33 discards any path handed to the app and restores whatever project it
    # last showed, so this only launches or reveals it. The registration above is
    # what puts the worktree in the sidebar — say so rather than implying wtw
    # navigated there.
    #
    # Under T3's default repository grouping the sidebar row is the repo, with the
    # branch on each thread, so pointing at the pretty name would be misleading.
    # WorktreeEntry is $null when the target is the repo's main checkout.
    $branch = Get-WtwPropertyValue -Object $Target.WorktreeEntry -Name 'branch'
    $where = if (-not (Test-WtwT3GroupingHidesTitles -WorkspaceRoot $fullDir)) {
        "pick '$prettyName' in the sidebar"
    } elseif ($branch) {
        "find it under your repo, on branch '$branch'"
    } else {
        'find it under your repo in the sidebar'
    }

    if ($IsMacOS) {
        Write-Host "  Launching ${appName} — $where" -ForegroundColor Green
        & open -a $appName
        return
    }

    if ($IsWindows) {
        $exe = Find-WtwT3WindowsExecutable
        if (-not $exe) {
            Write-Error 'T3 Code not found. Install it with: winget install T3Tools.T3Code'
            return
        }
        Write-Host "  Launching T3 Code — $where" -ForegroundColor Green
        Start-Process -FilePath $exe
        return
    }

    Write-Warning 'T3 Code does not ship a Linux build — project registration only.'
}
