function Install-Wtw {
    <#
    .SYNOPSIS
        Install or update wtw globally to ~/.wtw/module/.
    .DESCRIPTION
        Copies the wtw module (public, private, completions, and root psm1) to
        ~/.wtw/module/ and adds a profile loader snippet to the PowerShell profile.
        Blocks self-install when already running from the global copy.
    .PARAMETER SkipProfile
        Do not modify the PowerShell profile (skip adding the auto-loader snippet).
    .EXAMPLE
        wtw install
        Install wtw globally and add the profile loader.
    .EXAMPLE
        wtw install --skip-profile
        Install wtw globally without modifying the PowerShell profile.
    #>
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

    # Detect installed editors and offer to install Peacock extension
    Write-Host ''
    Write-Host '  Checking editors...' -ForegroundColor Cyan

    $editorDefs = @(
        @{ Name = 'VS Code';      Cmd = 'code';        ExtCmd = 'code' }
        @{ Name = 'Cursor';       Cmd = 'cursor';      ExtCmd = 'cursor' }
        @{ Name = 'Antigravity';  Cmd = 'antigravity';  ExtCmd = 'antigravity' }
        @{ Name = 'Windsurf';     Cmd = 'windsurf';    ExtCmd = 'windsurf' }
        @{ Name = 'VSCodium';     Cmd = 'codium';      ExtCmd = 'codium' }
    )

    $peacockExtId = 'johnpapa.vscode-peacock'
    $installedEditors = @()

    foreach ($ed in $editorDefs) {
        $found = Get-Command $ed.Cmd -ErrorAction SilentlyContinue
        if ($found) {
            $installedEditors += $ed
            Write-Host "    $($ed.Name) ($($ed.Cmd))" -ForegroundColor Green -NoNewline

            # Check if Peacock is already installed
            $extensions = & $ed.ExtCmd --list-extensions 2>$null
            if ($extensions -and ($extensions -match $peacockExtId)) {
                Write-Host "  — Peacock installed" -ForegroundColor DarkGray
            } else {
                Write-Host "  — Peacock NOT installed" -ForegroundColor Yellow
            }
        }
    }

    if ($installedEditors.Count -eq 0) {
        Write-Host '    No supported editors found (code, cursor, antigravity, windsurf, codium).' -ForegroundColor Yellow
        Write-Host '    wtw works best with the Peacock extension for workspace colors.' -ForegroundColor DarkGray
    } else {
        # Check if any editors are missing Peacock
        $needPeacock = @()
        foreach ($ed in $installedEditors) {
            $extensions = & $ed.ExtCmd --list-extensions 2>$null
            if (-not $extensions -or -not ($extensions -match $peacockExtId)) {
                $needPeacock += $ed
            }
        }

        if ($needPeacock.Count -gt 0) {
            Write-Host ''
            $names = ($needPeacock | ForEach-Object { $_.Name }) -join ', '
            Write-Host "  Peacock extension is recommended for workspace colors." -ForegroundColor Yellow
            Write-Host "  Missing in: $names" -ForegroundColor DarkGray
            $install = Read-Host "  Install Peacock extension? [y/N]"
            if ($install -in @('y', 'Y', 'yes')) {
                foreach ($ed in $needPeacock) {
                    Write-Host "    Installing in $($ed.Name)..." -ForegroundColor Cyan -NoNewline
                    & $ed.ExtCmd --install-extension $peacockExtId 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host " done" -ForegroundColor Green
                    } else {
                        Write-Host " failed" -ForegroundColor Red
                    }
                }
            }
        } else {
            Write-Host '  Peacock extension found in all editors.' -ForegroundColor Green
        }
    }

    Write-Host ''
    Write-Host '  Done! Restart your terminal or run:' -ForegroundColor Green
    Write-Host "    Import-Module $(Join-Path $installDir 'wtw.psm1') -Force" -ForegroundColor DarkGray
    Write-Host ''
}
