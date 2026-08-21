function Update-Wtw {
    <#
    .SYNOPSIS
        Update the installed wtw to the latest PowerShell Gallery release.
    .DESCRIPTION
        `wtw install` copies a source checkout into ~/.wtw/module. `wtw update`
        is the other half: it replaces whatever is in ~/.wtw/module with the
        published Gallery package, whether that copy came from the Gallery or was
        hand-installed from a checkout.

        It materialises the package into ~/.wtw/module rather than leaving it on
        PSModulePath because every loader wtw installs — the profile snippet, the
        zsh and bash wrappers, the Windows cmd shim — imports
        ~/.wtw/module/wtw.psm1 by explicit path. An `Install-Module wtw` that
        lands somewhere else updates a copy none of them ever load, which is the
        exact trap this command exists to close.

        A local build that is newer than the Gallery is a normal state for anyone
        working on wtw itself, and is reported as current, not as a problem.
    .PARAMETER Check
        Report versions and exit without changing anything.
    .PARAMETER Yes
        Skip the confirmation prompt.
    .PARAMETER Force
        Reinstall from the Gallery even when the installed version already
        matches, and bypass the 24h version cache.
    .EXAMPLE
        wtw update
        Compare against the Gallery and offer to replace the installed copy.
    .EXAMPLE
        wtw update --check
        Show where wtw is installed from and whether it is current.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch] $Check,
        [switch] $Yes,
        [switch] $Force
    )

    $installRoot = Join-Path $HOME '.wtw' 'module'
    $info = Get-WtwInstallInfo -IncludeGalleryCopies
    $status = Get-WtwUpdateStatus -Force:$Force

    # The version that matters is the one in ~/.wtw/module — the copy every
    # loader imports — not the checkout this command happens to be running from.
    $installed = if ($info.ModuleRoot -eq $info.InstallRoot) {
        $info
    } else {
        Get-WtwInstallInfo -ModuleRoot $installRoot
    }
    $installedPresent = Test-Path -LiteralPath (Join-Path $installRoot 'wtw.psm1') -PathType Leaf

    Write-Host ''
    Write-Host '  wtw update' -ForegroundColor Cyan
    if ($installedPresent) {
        $originLabel = switch ($installed.Flavour) {
            'Gallery' { 'PowerShell Gallery' }
            default { if ($installed.SourcePath) { "local checkout ($($installed.SourcePath))" } else { 'local checkout' } }
        }
        Write-Host ("    Installed:  {0}  [{1}]" -f ($installed.Version ?? 'unknown'), $originLabel)
        Write-Host ("    Location:   {0}" -f $installRoot) -ForegroundColor DarkGray
    } else {
        Write-Host '    Installed:  not installed globally' -ForegroundColor Yellow
    }

    if ($status.Status -ne 'Available' -or $null -eq $status.LatestVersion) {
        Write-Host '    Gallery:    unreachable — try again when online.' -ForegroundColor Yellow
        Write-Host ''
        return
    }
    Write-Host ("    Gallery:    {0}" -f $status.LatestVersion)

    if ($info.Flavour -eq 'Repo') {
        Write-Host ("    Running from a checkout at {0}" -f $info.ModuleRoot) -ForegroundColor DarkGray
    }

    Write-WtwShadowWarning -Info $info -Yes:$Yes -Check:$Check

    $current = $installed.Version
    $upToDate = $installedPresent -and $null -ne $current -and $status.LatestVersion -le $current

    if ($upToDate -and -not $Force) {
        # Equal, or a local build ahead of the Gallery. Neither is a problem, so
        # neither gets a warning.
        if ($status.LatestVersion -lt $current) {
            Write-Host ("    {0} is newer than the published {1} — nothing to do." -f $current, $status.LatestVersion) -ForegroundColor Green
        } else {
            Write-Host '    Up to date.' -ForegroundColor Green
        }
        Write-Host ''
        return
    }

    if ($Check) {
        Write-Host ("    Update available: {0} -> {1}   (run: wtw update)" -f ($current ?? 'none'), $status.LatestVersion) -ForegroundColor Cyan
        Write-Host ''
        return
    }

    Write-Host ''
    if ($installed.Flavour -eq 'Manual' -and $installedPresent) {
        Write-Host '  The installed copy was hand-installed from a checkout.' -ForegroundColor Yellow
        Write-Host '  Updating replaces it with the published Gallery package.' -ForegroundColor DarkGray
        Write-Host '  To keep tracking your checkout instead, run `wtw install` from it.' -ForegroundColor DarkGray
    }

    if (-not $Yes) {
        # ${...} around the path: a bare "$installRoot?" parses the trailing
        # question mark as part of the variable name.
        $prompt = "  Install wtw $($status.LatestVersion) from the PowerShell Gallery into ${installRoot}? [y/N]"
        if ((Read-Host $prompt) -notin @('y', 'Y', 'yes')) {
            Write-Host '  Cancelled.' -ForegroundColor DarkGray
            Write-Host ''
            return
        }
    }

    if (-not $PSCmdlet.ShouldProcess($installRoot, "Install wtw $($status.LatestVersion) from the PowerShell Gallery")) {
        return
    }

    $staged = Save-WtwGalleryPackage -Version $status.LatestVersion
    if (-not $staged) {
        Write-Host ''
        return
    }

    try {
        if (Install-WtwStagedModule -StagedRoot $staged -InstallRoot $installRoot) {
            Write-WtwInstallRecord -InstallRoot $installRoot -Origin 'Gallery' -Version $status.LatestVersion
            Write-Host ("  wtw {0} installed to {1}" -f $status.LatestVersion, $installRoot) -ForegroundColor Green
            Write-Host '  Restart your terminal to load it.' -ForegroundColor DarkGray
        }
    } finally {
        Remove-Item -LiteralPath (Split-Path -Parent $staged) -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host ''
}
