# wtw — Git Worktree + Workspace Manager
# Module loader: dot-source public/ and private/ functions.
#
# IMPORTANT: Everything ABOVE the `return` in the Windows PowerShell branch must
# stay parseable AND runnable by Windows PowerShell 5.1 (Desktop edition). The
# rest of the module (the dot-sourced public/ + private/ files) uses PowerShell
# 7+ syntax (??, ternary, &&) and would fail to even parse under 5.1, so it is
# only dot-sourced once we have confirmed we are on PowerShell 7+ (Core).
#
# Net effect: running `wtw ...` from Windows PowerShell transparently hands off
# to pwsh (PowerShell 7), or — when pwsh is not installed — explains how to get
# it. From pwsh itself, the full module loads normally.

$script:WtwModuleRoot = $PSScriptRoot

function Get-WtwPwshExecutable {
    # 5.1-safe discovery of a PowerShell 7+ (pwsh) executable.
    # Returns the full path, or $null when pwsh is not installed.
    $cmd = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'PowerShell\7\pwsh.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\PowerShell\7\pwsh.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }

    return $null
}

# Edition detection. $PSVersionTable.PSEdition is 'Core' on PowerShell 7+ (all
# platforms) and 'Desktop' on Windows PowerShell 5.1. Treat anything that is not
# explicitly Core as Desktop (covers ancient hosts that predate PSEdition).
$wtwEdition = $PSVersionTable.PSEdition
if (-not $wtwEdition) { $wtwEdition = 'Desktop' }

if ($wtwEdition -ne 'Core') {
    # ----- Windows PowerShell (Desktop): thin pwsh hand-off shim ---------------
    $script:WtwPwshPath = Get-WtwPwshExecutable

    function Invoke-Wtw {
        $pwshPath = $script:WtwPwshPath

        if (-not $pwshPath) {
            Write-Host ''
            Write-Host '  wtw requires PowerShell 7+ (pwsh).' -ForegroundColor Red
            Write-Host "  You're running Windows PowerShell $($PSVersionTable.PSVersion), and pwsh is not installed." -ForegroundColor Yellow
            Write-Host ''
            Write-Host '  Install PowerShell 7 with:' -ForegroundColor Cyan
            Write-Host '    winget install --id Microsoft.PowerShell --source winget' -ForegroundColor White
            Write-Host ''

            $answer = Read-Host '  Install it now via winget? [y/N]'
            if ($answer -match '^(y|yes)$') {
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    & winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements
                    Write-Host ''
                    Write-Host '  Done. Open a new terminal (or run pwsh) and re-run your wtw command.' -ForegroundColor Green
                } else {
                    Write-Host '  winget is not available. Install PowerShell 7 manually: https://aka.ms/powershell' -ForegroundColor Red
                }
            }
            return
        }

        $modulePath = Join-Path $script:WtwModuleRoot 'wtw.psm1'

        # No arguments: drop the user into a pwsh session in this console
        # (auto-switch), with the wtw module loaded and help shown.
        if ($args.Count -eq 0) {
            Write-Host '  wtw: switching this console to PowerShell 7 (pwsh)...' -ForegroundColor DarkGray
            & $pwshPath -NoLogo -NoExit -Command "Import-Module '$modulePath' -DisableNameChecking; wtw"
            return
        }

        # Re-quote each argument so spaces and quotes survive the hand-off.
        $quoted = @()
        foreach ($a in $args) { $quoted += "'" + ([string]$a).Replace("'", "''") + "'" }
        $argLine = $quoted -join ' '

        Write-Host '  wtw: running under PowerShell 7 (pwsh)...' -ForegroundColor DarkGray
        & $pwshPath -NoLogo -NoProfile -Command "Import-Module '$modulePath' -DisableNameChecking; Invoke-Wtw $argLine"
    }

    # The installed profile loader calls Register-WtwProfile right after import;
    # provide a no-op so Windows PowerShell sessions don't error on startup.
    function Register-WtwProfile { }

    Set-Alias -Name wtw -Value Invoke-Wtw -Scope Global -Force
    Export-ModuleMember -Function 'Invoke-Wtw', 'Register-WtwProfile' -Alias 'wtw'
    return
}

# ----- PowerShell 7+ (Core): load the full module -----------------------------

# Keep module behavior deterministic regardless of the importing session's
# strict-mode setting. This also makes the regular test suite exercise the same
# semantics as strict repository session scripts.
Set-StrictMode -Version Latest

$script:WtwCmuxApplyingFromInit = $false

$dotSourceParams = @{
    Filter      = '*.ps1'
    Recurse     = $true
    ErrorAction = 'Stop'
}

$public = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'public') @dotSourceParams)
$private = @()
$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'private'
if (Test-Path $privatePath) {
    $private = @(Get-ChildItem -Path $privatePath @dotSourceParams)
}

foreach ($import in @($private + $public)) {
    try {
        . $import.FullName
    } catch {
        throw "Unable to dot source [$($import.FullName)]"
    }
}

Export-ModuleMember -Function $public.BaseName

Set-Alias -Name wtw -Value Invoke-Wtw -Scope Global -Force
Export-ModuleMember -Alias wtw

# Load tab completion
$completionPath = Join-Path $PSScriptRoot 'completions' 'wtw.auto-completion.ps1'
if (Test-Path $completionPath) {
    . $completionPath
}
