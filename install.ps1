# wtw installer — Windows
# Usage (from PowerShell 5+ or pwsh):
#   irm https://raw.githubusercontent.com/serrnovik/wtw/main/install.ps1 | iex
#
# Or download and run:
#   Invoke-WebRequest https://raw.githubusercontent.com/serrnovik/wtw/main/install.ps1 -OutFile install.ps1
#   .\install.ps1

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '  wtw — Git Worktree + Workspace Manager' -ForegroundColor Cyan
Write-Host '  ───────────────────────────────────────' -ForegroundColor DarkGray
Write-Host ''

$WtwRepo = 'https://github.com/serrnovik/wtw.git'
$WtwDir = Join-Path $HOME '.wtw' 'source'

# --- Check / install git ---
if (-not (Get-Command 'git' -ErrorAction SilentlyContinue)) {
    Write-Host '  Git is required but not found.' -ForegroundColor Red

    # Try winget first
    if (Get-Command 'winget' -ErrorAction SilentlyContinue) {
        $install = Read-Host '  Install Git via winget? [Y/n]'
        if (-not $install -or $install -in @('y', 'Y', 'yes')) {
            Write-Host '  Installing Git...' -ForegroundColor Cyan
            winget install --id Git.Git --source winget --accept-package-agreements --accept-source-agreements
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
        }
    }

    if (-not (Get-Command 'git' -ErrorAction SilentlyContinue)) {
        Write-Host '  Git still not found. Install from: https://git-scm.com/downloads/win' -ForegroundColor Yellow
        Write-Host ''
        return
    }
}

# --- Check / install pwsh (PowerShell 7+) ---
$needPwsh = $PSVersionTable.PSVersion.Major -lt 7

if ($needPwsh) {
    Write-Host "  PowerShell 7+ is required (you have $($PSVersionTable.PSVersion))." -ForegroundColor Yellow

    if (Get-Command 'winget' -ErrorAction SilentlyContinue) {
        $install = Read-Host '  Install PowerShell 7 via winget? [Y/n]'
        if (-not $install -or $install -in @('y', 'Y', 'yes')) {
            Write-Host '  Installing PowerShell 7...' -ForegroundColor Cyan
            winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements
            Write-Host ''
            Write-Host '  PowerShell 7 installed. Re-run this installer from pwsh:' -ForegroundColor Green
            Write-Host '    pwsh -Command "irm https://raw.githubusercontent.com/serrnovik/wtw/main/install.ps1 | iex"' -ForegroundColor DarkGray
            Write-Host ''
            return
        }
    }

    # dotnet tool fallback
    if (Get-Command 'dotnet' -ErrorAction SilentlyContinue) {
        $install = Read-Host '  Install PowerShell 7 via dotnet tool? [Y/n]'
        if (-not $install -or $install -in @('y', 'Y', 'yes')) {
            dotnet tool install --global PowerShell
            Write-Host ''
            Write-Host '  Re-run from pwsh:' -ForegroundColor Green
            Write-Host '    pwsh -Command "irm https://raw.githubusercontent.com/serrnovik/wtw/main/install.ps1 | iex"' -ForegroundColor DarkGray
            Write-Host ''
            return
        }
    }

    Write-Host '  Install PowerShell 7: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows' -ForegroundColor Yellow
    Write-Host ''
    return
}

Write-Host "  git:  $(git --version)"
Write-Host "  pwsh: PowerShell $($PSVersionTable.PSVersion)"
Write-Host ''

# --- Clone or update wtw ---
if (Test-Path (Join-Path $WtwDir '.git')) {
    Write-Host '  Updating wtw source...' -ForegroundColor Cyan
    git -C $WtwDir pull --ff-only --quiet
} else {
    Write-Host '  Cloning wtw...' -ForegroundColor Cyan
    if (Test-Path $WtwDir) { Remove-Item $WtwDir -Recurse -Force }
    $parentDir = Split-Path $WtwDir -Parent
    if (-not (Test-Path $parentDir)) { New-Item -Path $parentDir -ItemType Directory -Force | Out-Null }
    git clone --depth 1 --quiet $WtwRepo $WtwDir
}

# --- Run wtw install ---
Write-Host '  Running wtw install...' -ForegroundColor Cyan
Write-Host ''

Import-Module (Join-Path $WtwDir 'wtw.psm1') -Force -DisableNameChecking
Install-Wtw

Write-Host '  Restart your terminal to activate wtw.' -ForegroundColor Green
Write-Host ''
