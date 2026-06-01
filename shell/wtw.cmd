@echo off
REM wtw -- cmd.exe shim. Delegates to pwsh for all logic.
REM For 'wtw go <name>' or implicit-go, pwsh resolves the path and cmd cd's.
REM For every other subcommand, output is passed through unchanged.
REM
REM Installed to %USERPROFILE%\.wtw\cmd\wtw.cmd and put on PATH by 'wtw install'.

setlocal
set "_WTW_MODULE=%USERPROFILE%\.wtw\module\wtw.psm1"

if not exist "%_WTW_MODULE%" (
    echo wtw: module not found at "%_WTW_MODULE%". Run 'wtw install' from PowerShell. 1>&2
    exit /b 1
)

REM No args -> show help via pwsh
if "%~1"=="" goto :passthrough

set "_FIRST=%~1"

REM Known subcommands that don't need cmd-side cd. Pad with spaces so findstr
REM can match whole tokens.
set "_NOCD= init add create list ls open cursor cur code co antigravity anti ag windsurf wind ws codium vscodium sourcegit sgit sg codex cmux cm wmux wm claude cowork claudecode ccode t3 t3code remove rm delete del unregister unreg workspace copy color sync clean install update skill sbx help -h --help "
echo  %_NOCD% | findstr /I /C:" %_FIRST% " >nul
if not errorlevel 1 goto :passthrough

REM wtw go and implicit-go both arrive here. If --new-tab is in the args,
REM pwsh handles the spawn; cmd.exe shouldn't cd.
echo  %* | findstr /I /C:"--new-tab" >nul
if not errorlevel 1 goto :passthrough

REM Otherwise: resolve the target path via pwsh and cd /d to it.
set "_NAME=%_FIRST%"
if /i "%_FIRST%"=="go" set "_NAME=%~2"
if "%_NAME%"=="" goto :passthrough

for /f "usebackq delims=" %%P in (`pwsh -NoLogo -NoProfile -Command "Import-Module '%_WTW_MODULE%' -DisableNameChecking; Invoke-Wtw __resolve_path '%_NAME%'" 2^>nul`) do set "_WTW_PATH=%%P"

if not defined _WTW_PATH (
    echo wtw: could not resolve "%_NAME%" 1>&2
    exit /b 1
)

endlocal & cd /d "%_WTW_PATH%" & echo Switched to: %_WTW_PATH%
exit /b 0

:passthrough
pwsh -NoLogo -NoProfile -Command "Import-Module '%_WTW_MODULE%' -DisableNameChecking; Invoke-Wtw %*"
exit /b %ERRORLEVEL%
