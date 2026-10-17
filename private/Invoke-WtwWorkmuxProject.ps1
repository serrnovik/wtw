# workmux integration for wtw.
#
# workmux (https://workmux.raine.dev) pairs git worktrees with tmux windows and
# adds an agent status sidebar/dashboard (`workmux sidebar`, `workmux dashboard`).
# It reads `git worktree list`, so wtw's worktrees (and the main checkout) are
# already known to it by directory name:
#   workmux open <dir-name>   -> "Opened tmux window for ..." or
#                                "Switched to existing tmux window for ..."
# It needs a running tmux server, but not a tmux client: from outside tmux the
# window opens in the server's session. With no server, wtw starts
# `tmux new-session` in a new Ghostty window first. workmux slugs window names
# (emoji become words), so wtw keeps its default `wm-<dir>` names.

function Get-WtwWorkmuxExe {
    [CmdletBinding()]
    param()

    if ($env:WTW_WORKMUX -and (Test-Path $env:WTW_WORKMUX)) { return $env:WTW_WORKMUX }

    $cmd = Get-Command workmux -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    $homeDir = if ($HOME) { $HOME } else { $env:USERPROFILE }
    if ($homeDir) {
        foreach ($dir in @('.cargo/bin', '.local/bin')) {
            $candidate = Join-Path (Join-Path $homeDir $dir) 'workmux'
            if (Test-Path $candidate) { return $candidate }
        }
    }

    return $null
}

function Test-WtwTmuxServer {
    <# .SYNOPSIS True when a tmux server with at least one session is running. #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command tmux -CommandType Application -ErrorAction SilentlyContinue)) { return $false }
    & tmux has-session 2>$null
    return $LASTEXITCODE -eq 0
}

function Start-WtwTmuxServer {
    <#
    .SYNOPSIS
        Start a tmux session in a new Ghostty window and wait for the server.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [int] $TimeoutSeconds = 10
    )

    if (-not (Get-Command tmux -CommandType Application -ErrorAction SilentlyContinue)) { return $false }
    if (-not (Start-WtwGhosttyWindow -WorkingDirectory $ProjectPath -Command @('tmux', 'new-session', '-A', '-s', 'wtw'))) {
        return $false
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 250
        if (Test-WtwTmuxServer) { return $true }
    }
    return $false
}

function Invoke-WtwWorkmuxCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkingDirectory,
        [Parameter(Mandatory)][string[]] $ArgumentList
    )

    $exe = Get-WtwWorkmuxExe
    if (-not $exe) {
        return [PSCustomObject]@{ ExitCode = 127; Output = 'workmux not found' }
    }

    Write-Verbose "workmux command (in $WorkingDirectory): $exe $($ArgumentList -join ' ')"
    Push-Location -LiteralPath $WorkingDirectory
    try {
        $output = & $exe @ArgumentList 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($null -eq $exitCode) { $exitCode = 0 }
    $text = (@($output) | ForEach-Object { "$_" }) -join [Environment]::NewLine
    return [PSCustomObject]@{ ExitCode = $exitCode; Output = $text.Trim() }
}

function Open-WtwWorkmuxProject {
    <#
    .SYNOPSIS
        Open a wtw target as a workmux tmux window: `workmux open <dir-name>`
        switches to the existing window or creates one.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath
    )

    if (-not (Get-WtwWorkmuxExe)) {
        return [PSCustomObject]@{ Success = $false; Created = $false; Started = $false; Reason = 'workmux not found' }
    }

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath).TrimEnd('/', '\')
    $name = Split-Path -Leaf $fullPath
    $started = $false
    if (-not (Test-WtwTmuxServer)) {
        if (-not (Start-WtwTmuxServer -ProjectPath $fullPath)) {
            return [PSCustomObject]@{
                Success = $false; Created = $false; Started = $false; Path = $fullPath; Name = $name
                Reason  = 'no tmux server is running and Ghostty could not start one. Run `tmux` in a terminal, then retry.'
            }
        }
        $started = $true
    }

    $result = Invoke-WtwWorkmuxCommand -WorkingDirectory $fullPath -ArgumentList @('open', $name)
    if ($result.ExitCode -ne 0) {
        return [PSCustomObject]@{ Success = $false; Created = $false; Started = $started; Path = $fullPath; Name = $name; Reason = $result.Output }
    }

    return [PSCustomObject]@{
        Success = $true; Created = ($result.Output -notmatch 'existing'); Started = $started
        Path = $fullPath; Name = $name; Reason = $null
    }
}
