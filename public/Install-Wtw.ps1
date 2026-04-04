function Install-Wtw {
    [CmdletBinding()]
    param(
        [switch] $SkipProfile
    )

    $installDir = Join-Path $HOME '.wtw' 'module'
    $sourceDir = Join-Path $PSScriptRoot '..'  # parent of public/ = module root
    $sourceDir = [System.IO.Path]::GetFullPath($sourceDir)
    $installDirResolved = [System.IO.Path]::GetFullPath($installDir)
    $profilePath = if ($PROFILE) { $PROFILE } else { Join-Path $HOME '.config' 'powershell' 'Microsoft.PowerShell_profile.ps1' }

    # Prevent self-install (running from the global install itself)
    if ($sourceDir -eq $installDirResolved) {
        Write-Host ''
        Write-Host '  Cannot install from the global copy — it would delete itself.' -ForegroundColor Red
        Write-Host '  Run from the repo source instead:' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '    cd <repo>/devops/worktree-workspace' -ForegroundColor DarkGray
        Write-Host '    Import-Module ./wtw.psm1 -Force; wtw install' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host ''
    Write-Host '  Installing wtw...' -ForegroundColor Cyan
    Write-Host "  Source:  $sourceDir"
    Write-Host "  Target:  $installDir"

    # Remove old install
    if (Test-Path $installDir) {
        Remove-Item -Path $installDir -Recurse -Force
    }

    # Copy module files
    New-Item -Path $installDir -ItemType Directory -Force | Out-Null

    $dirs = @('public', 'private', 'completions')
    foreach ($dir in $dirs) {
        $src = Join-Path $sourceDir $dir
        if (Test-Path $src) {
            $dest = Join-Path $installDir $dir
            Copy-Item -Path $src -Destination $dest -Recurse -Force
        }
    }

    # Copy module root file
    $rootFile = Join-Path $sourceDir 'wtw.psm1'
    Copy-Item -Path $rootFile -Destination (Join-Path $installDir 'wtw.psm1') -Force

    Write-Host "  Module installed to $installDir" -ForegroundColor Green

    # Check/update profile
    if (-not $SkipProfile) {
        $profileSnippet = @'

# wtw — worktree + workspace manager (global install)
$_wtwModule = Join-Path $HOME '.wtw' 'module' 'wtw.psm1'
if (Test-Path $_wtwModule) {
    Import-Module $_wtwModule -Force -DisableNameChecking -Verbose:$false -Debug:$false 1>$null 4>$null 5>$null 6>$null
    Register-WtwProfile
}
'@

        if (Test-Path $profilePath) {
            $profileContent = Get-Content $profilePath -Raw
            if ($profileContent -match 'wtw.*worktree.*workspace.*manager') {
                Write-Host '  Profile already has wtw loader — skipping.' -ForegroundColor DarkGray
            } else {
                Add-Content -Path $profilePath -Value $profileSnippet -Encoding utf8
                Write-Host "  Added loader to profile: $profilePath" -ForegroundColor Green
            }
        } else {
            # Create profile if it doesn't exist
            $profileDir = Split-Path $profilePath -Parent
            if (-not (Test-Path $profileDir)) {
                New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
            }
            Set-Content -Path $profilePath -Value $profileSnippet -Encoding utf8
            Write-Host "  Created profile with wtw loader: $profilePath" -ForegroundColor Green
        }
    }

    Write-Host ''
    Write-Host '  Done! Restart your terminal or run:' -ForegroundColor Green
    Write-Host "    Import-Module $(Join-Path $installDir 'wtw.psm1') -Force" -ForegroundColor DarkGray
    Write-Host ''
}
