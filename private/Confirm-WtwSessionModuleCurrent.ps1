function Test-WtwTruthyEnvFlag {
    <#
    .SYNOPSIS
        True when an env var is set to a non-empty value other than 0/false/no.
    #>
    [CmdletBinding()]
    param(
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return $Value.Trim() -notin @('0', 'false', 'no')
}

function Test-WtwIsPesterRun {
    <#
    .SYNOPSIS
        True when the current call stack is inside Pester.
    .DESCRIPTION
        Auto-reload must not replace the checkout under test with ``~/.wtw/module``.
        Matching Pester's own scripts on the call stack is enough, and is cheap.
    #>
    [CmdletBinding()]
    param()

    try {
        foreach ($frame in Get-PSCallStack) {
            $src = [string]$frame.ScriptName
            if ([string]::IsNullOrWhiteSpace($src)) { continue }
            if ($src -match '[\\/]Pester[\\/]' -or $src -match 'Pester\.psm1$') {
                return $true
            }
        }
    } catch {
        return $false
    }

    return $false
}

function Get-WtwSessionModuleStatus {
    <#
    .SYNOPSIS
        Compare the version this session loaded with the copies on disk.
    .DESCRIPTION
        ``$script:WtwLoadedManifestVersion`` is snapped when the module imports.
        After ``wtw update``, ``wtw install``, or an in-place overwrite, the
        files on disk can be newer than the functions still in memory.

        ReloadRoot is the copy this session should be running:
        the loaded checkout when ``WTW_USE_REPO_MODULE`` is set, otherwise the
        newer of that checkout and ``~/.wtw/module``.
    #>
    [CmdletBinding()]
    param(
        [string] $ModuleRoot,

        [string] $InstallRoot,

        $LoadedVersion
    )

    if ([string]::IsNullOrWhiteSpace($ModuleRoot)) {
        $ModuleRoot = $script:WtwModuleRoot
    }
    if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
        $InstallRoot = Join-Path $HOME '.wtw' 'module'
    }
    if (-not $PSBoundParameters.ContainsKey('LoadedVersion')) {
        $LoadedVersion = $script:WtwLoadedManifestVersion
    }

    $loaded = $null
    if ($LoadedVersion -is [version]) {
        $loaded = $LoadedVersion
    } elseif ($null -ne $LoadedVersion) {
        [void][version]::TryParse([string]$LoadedVersion, [ref] $loaded)
    }

    $resolvedRoot = try { [IO.Path]::GetFullPath($ModuleRoot) } catch { $ModuleRoot }
    $resolvedInstall = try { [IO.Path]::GetFullPath($InstallRoot) } catch { $InstallRoot }
    $diskVersion = Get-WtwManifestVersion -ModuleRoot $resolvedRoot
    $installModule = Join-Path $resolvedInstall 'wtw.psm1'
    $installPresent = Test-Path -LiteralPath $installModule -PathType Leaf
    $installVersion = if ($installPresent) { Get-WtwManifestVersion -ModuleRoot $resolvedInstall } else { $null }
    $sameRoot = [string]::Equals($resolvedRoot, $resolvedInstall, [StringComparison]::OrdinalIgnoreCase)
    # Same truthiness as Restore-WtwInstalledModule: any non-empty value opts in.
    $useRepo = -not [string]::IsNullOrWhiteSpace([string]$env:WTW_USE_REPO_MODULE)

    $reloadRoot = $resolvedRoot
    $reloadVersion = $diskVersion
    $reason = 'loaded-root'
    if (-not $useRepo -and $installPresent -and -not $sameRoot) {
        if ($null -ne $installVersion -and ($null -eq $diskVersion -or $installVersion -gt $diskVersion)) {
            $reloadRoot = $resolvedInstall
            $reloadVersion = $installVersion
            $reason = 'install'
        }
    }

    $stale = $null -ne $loaded -and $null -ne $reloadVersion -and $reloadVersion -gt $loaded

    [pscustomobject]@{
        LoadedVersion     = $loaded
        LoadedRoot        = $resolvedRoot
        DiskVersion       = $diskVersion
        InstallRoot       = $resolvedInstall
        InstallVersion    = $installVersion
        InstallPresent    = $installPresent
        ReloadRoot        = $reloadRoot
        ReloadVersion     = $reloadVersion
        ReloadModulePath  = Join-Path $reloadRoot 'wtw.psm1'
        SameRoot          = $sameRoot
        UseRepoModule     = $useRepo
        Reason            = $reason
        Stale             = $stale
    }
}

function Import-WtwSessionModule {
    <#
    .SYNOPSIS
        Force-import a wtw.psm1 into the current session.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ModulePath
    )

    Import-Module $ModulePath -Global -Force -DisableNameChecking -Verbose:$false -Debug:$false 1>$null 4>$null 5>$null 6>$null
}

function Write-WtwSessionReloadNotice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Status,

        [switch] $Reloaded
    )

    $from = if ($null -ne $Status.LoadedVersion) { $Status.LoadedVersion.ToString() } else { 'unknown' }
    $to = if ($null -ne $Status.ReloadVersion) { $Status.ReloadVersion.ToString() } else { 'unknown' }
    if ($Reloaded) {
        if ($from -ne $to) {
            Write-Host ("  Reloaded wtw {0} → {1} in this session." -f $from, $to) -ForegroundColor DarkGray
        } else {
            Write-Host ("  Reloaded wtw {0} in this session." -f $to) -ForegroundColor DarkGray
        }
        return
    }

    Write-Host ''
    Write-Host ("  This session loaded wtw {0}; {1} is on disk." -f $from, $to) -ForegroundColor Yellow
    Write-Host '  Reload: wtw reload' -ForegroundColor DarkGray
}

function Confirm-WtwSessionModuleCurrent {
    <#
    .SYNOPSIS
        Reload wtw in this session when the imported copy is older than disk.
    .DESCRIPTION
        Same-folder updates (``wtw update`` / an overwrite of ``~/.wtw/module``
        while this shell still holds the old functions) are imported automatically
        and the original command is re-run against the new functions.

        A checkout-imported session that is older than ``~/.wtw/module`` is not
        yanked automatically (that would surprise ``WTW_USE_REPO_MODULE`` and
        Pester). It prints ``wtw reload`` once instead.

        Returns ``$true`` when the original command was already re-dispatched
        (the caller must return). ``wtw reload`` passes ``-Force`` and does not
        re-dispatch.
    #>
    [CmdletBinding()]
    param(
        [object[]] $OriginalArgs = @(),

        [switch] $Force
    )

    try {
        if (-not $Force) {
            if (Test-WtwTruthyEnvFlag -Value $env:WTW_SESSION_RELOADING) {
                return $false
            }
            if (Test-WtwTruthyEnvFlag -Value $env:WTW_NO_SESSION_RELOAD) {
                return $false
            }
            if (Test-WtwTruthyEnvFlag -Value $env:CI) {
                return $false
            }
            if (Test-WtwIsPesterRun) {
                return $false
            }
        }

        $status = Get-WtwSessionModuleStatus
        if (-not $Force -and -not $status.Stale) {
            return $false
        }

        $reloadPath = [string]$status.ReloadModulePath
        if (-not (Test-Path -LiteralPath $reloadPath -PathType Leaf)) {
            return $false
        }

        $quiet = $false
        try { $quiet = [Console]::IsOutputRedirected } catch { $quiet = $false }

        # Auto-import only the copy this session already loaded. Switching to
        # ~/.wtw/module from a checkout is `wtw reload` / Restore-WtwInstalledModule.
        $samePath = [string]::Equals(
            $status.LoadedRoot,
            $status.ReloadRoot,
            [StringComparison]::OrdinalIgnoreCase
        )
        if (-not $Force -and -not $samePath) {
            if (-not $quiet -and -not $script:WtwSessionStaleHintShown) {
                $script:WtwSessionStaleHintShown = $true
                Write-WtwSessionReloadNotice -Status $status
            }
            return $false
        }

        Import-WtwSessionModule -ModulePath $reloadPath

        if ($Force -or -not $quiet) {
            Write-WtwSessionReloadNotice -Status $status -Reloaded
        }

        if ($Force) {
            return $true
        }

        $env:WTW_SESSION_RELOADING = '1'
        try {
            $invoke = Get-Command Invoke-Wtw -ErrorAction Stop
            if (@($OriginalArgs).Count -eq 0) {
                & $invoke
            } else {
                & $invoke @OriginalArgs
            }
        } finally {
            Remove-Item Env:WTW_SESSION_RELOADING -ErrorAction SilentlyContinue
        }

        return $true
    } catch {
        # A failed reload must not block the command the user typed.
        return $false
    }
}

function Invoke-WtwReloadSession {
    <#
    .SYNOPSIS
        Reload the wtw module in this PowerShell session.
    .DESCRIPTION
        Force-imports the copy this session should be running (the newer of the
        loaded checkout and ``~/.wtw/module``, unless ``WTW_USE_REPO_MODULE``).
        ``-Check`` only reports loaded vs disk vs install.
    #>
    [CmdletBinding()]
    param(
        [switch] $Check
    )

    $status = Get-WtwSessionModuleStatus

    if ($Check) {
        $loaded = if ($null -ne $status.LoadedVersion) { $status.LoadedVersion.ToString() } else { 'unknown' }
        $disk = if ($null -ne $status.DiskVersion) { $status.DiskVersion.ToString() } else { 'unknown' }
        $installed = if ($status.InstallPresent -and $null -ne $status.InstallVersion) {
            $status.InstallVersion.ToString()
        } elseif ($status.InstallPresent) {
            'unknown'
        } else {
            'none'
        }
        Write-Host ''
        Write-Host '  wtw session' -ForegroundColor Cyan
        Write-Host ("    loaded     {0}" -f $loaded)
        Write-Host ("    this copy  {0}   {1}" -f $disk, $status.LoadedRoot)
        Write-Host ("    installed  {0}   {1}" -f $installed, $status.InstallRoot)
        if ($status.Stale) {
            Write-Host '    stale      yes — run: wtw reload' -ForegroundColor Yellow
        } else {
            Write-Host '    stale      no' -ForegroundColor DarkGray
        }
        Write-Host ''
        return
    }

    Confirm-WtwSessionModuleCurrent -Force | Out-Null
}
