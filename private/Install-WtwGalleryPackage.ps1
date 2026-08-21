function Save-WtwGalleryPackage {
    <#
    .SYNOPSIS
        Download a wtw release from the PowerShell Gallery into a temp directory.
    .DESCRIPTION
        Returns the directory that actually contains wtw.psm1, or $null when the
        download fails. Save-PSResource and Save-Module lay the package out
        differently (flat versus a version subdirectory), so the module root is
        located by looking for the manifest rather than by assuming a shape.

        Nothing is downloaded straight into ~/.wtw/module: a half-written module
        directory is worse than an old one, so the package is staged first and
        only swapped in once it is complete.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [version] $Version,

        [string] $Repository = 'PSGallery'
    )

    $stagingParent = Join-Path ([IO.Path]::GetTempPath()) ('wtw-update-{0}' -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingParent -Force | Out-Null

    Write-Host ("  Downloading wtw {0} from the {1}..." -f $Version, $Repository) -ForegroundColor Cyan
    $saved = $false
    try {
        if (Get-Command Save-PSResource -ErrorAction SilentlyContinue) {
            Save-PSResource -Name 'wtw' -Version $Version.ToString() -Repository $Repository `
                -Path $stagingParent -TrustRepository -ErrorAction Stop
            $saved = $true
        } elseif (Get-Command Save-Module -ErrorAction SilentlyContinue) {
            Save-Module -Name 'wtw' -RequiredVersion $Version.ToString() -Repository $Repository `
                -Path $stagingParent -Force -ErrorAction Stop
            $saved = $true
        } else {
            Write-Host '  Neither Save-PSResource nor Save-Module is available.' -ForegroundColor Red
            Write-Host '  Install Microsoft.PowerShell.PSResourceGet, or update from a checkout with `wtw install`.' -ForegroundColor DarkGray
        }
    } catch {
        Write-Host ("  Download failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }

    if ($saved) {
        $manifest = Get-ChildItem -LiteralPath $stagingParent -Filter 'wtw.psm1' -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($manifest) {
            return $manifest.Directory.FullName
        }
        Write-Host '  The downloaded package did not contain wtw.psm1.' -ForegroundColor Red
    }

    Remove-Item -LiteralPath $stagingParent -Recurse -Force -ErrorAction SilentlyContinue
    return $null
}

function Install-WtwStagedModule {
    <#
    .SYNOPSIS
        Swap a staged module directory into the install root.
    .DESCRIPTION
        Moves the existing install aside before putting the new one in place, and
        puts it back if the move fails, so an interrupted update cannot leave the
        user with no wtw at all.

        ~/.wtw/shell is refreshed from the staged copy too. The zsh and bash
        wrappers live there, not in the module directory, and a wrapper that has
        drifted from the module it loads produces failures that look nothing like
        "the update half-finished".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $StagedRoot,

        [Parameter(Mandatory)]
        [string] $InstallRoot
    )

    $parent = Split-Path -Parent $InstallRoot
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $backup = Join-Path $parent ('.wtw-backup-{0}' -f [guid]::NewGuid().ToString('N'))
    $hadPrevious = Test-Path -LiteralPath $InstallRoot

    try {
        if ($hadPrevious) {
            Move-Item -LiteralPath $InstallRoot -Destination $backup -Force -ErrorAction Stop
        }
        Copy-Item -LiteralPath $StagedRoot -Destination $InstallRoot -Recurse -Force -ErrorAction Stop

        $shellSource = Join-Path $InstallRoot 'shell'
        if (Test-Path -LiteralPath $shellSource -PathType Container) {
            $shellDest = Join-Path $parent 'shell'
            if (Test-Path -LiteralPath $shellDest) {
                Remove-Item -LiteralPath $shellDest -Recurse -Force -ErrorAction SilentlyContinue
            }
            Copy-Item -LiteralPath $shellSource -Destination $shellDest -Recurse -Force -ErrorAction SilentlyContinue
        }

        if ($hadPrevious) {
            Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
        }
        return $true
    } catch {
        Write-Host ("  Install failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
        if ($hadPrevious -and (Test-Path -LiteralPath $backup)) {
            if (Test-Path -LiteralPath $InstallRoot) {
                Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
            Move-Item -LiteralPath $backup -Destination $InstallRoot -Force -ErrorAction SilentlyContinue
            Write-Host '  Previous install restored.' -ForegroundColor Yellow
        }
        return $false
    }
}

function Write-WtwShadowWarning {
    <#
    .SYNOPSIS
        Report wtw copies on PSModulePath that a bare Import-Module would pick
        over the one wtw actually loads, and offer to remove them.
    .DESCRIPTION
        `wtw install` and `wtw update` both target ~/.wtw/module, which is not on
        PSModulePath. A leftover `Install-Module wtw` therefore keeps answering
        `Import-Module wtw` — including from scripts and other modules — with a
        version nobody is maintaining. Silent until such a copy exists and its
        version differs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Info,

        [switch] $Yes,

        [switch] $Check
    )

    if (-not $Info.ShadowedBy) { return }

    Write-Host ''
    Write-Host '  Another wtw is installed on PSModulePath:' -ForegroundColor Yellow
    foreach ($copy in $Info.GalleryCopies) {
        Write-Host ("    {0}  {1}" -f $copy.Version, $copy.Path) -ForegroundColor DarkGray
    }
    Write-Host '  `Import-Module wtw` resolves to that copy, not the one your shell loads.' -ForegroundColor DarkGray

    if ($Check) { return }

    $remove = $Yes
    if (-not $remove) {
        $remove = (Read-Host '  Remove the PSModulePath copies? [y/N]') -in @('y', 'Y', 'yes')
    }
    if (-not $remove) { return }

    foreach ($copy in $Info.GalleryCopies) {
        try {
            Remove-Item -LiteralPath $copy.Path -Recurse -Force -ErrorAction Stop
            Write-Host ("    removed {0}" -f $copy.Path) -ForegroundColor Green
        } catch {
            Write-Host ("    could not remove {0}: {1}" -f $copy.Path, $_.Exception.Message) -ForegroundColor Red
        }
    }
}
