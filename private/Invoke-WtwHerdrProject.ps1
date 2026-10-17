# Herdr integration for wtw.
#
# Herdr (https://herdr.dev) is a terminal multiplexer for coding agents: a
# workspace sidebar that shows which agent is working, blocked or done. Its CLI
# reaches the running server over a socket from any shell and prints JSON:
#   herdr workspace list                      -> {result:{workspaces:[{workspace_id,label,...}]}}
#   herdr pane list                           -> {result:{panes:[{workspace_id,cwd,...}]}}
#   herdr workspace create --cwd <dir> --label <text> --focus
#   herdr workspace rename <id> <label>
#   herdr workspace focus <id>
# Failures are {error:{code,message}}. With no server up (server_not_running),
# wtw starts herdr in a new Ghostty window rooted at the target.

function Get-WtwHerdrExe {
    [CmdletBinding()]
    param()

    if ($env:WTW_HERDR -and (Test-Path $env:WTW_HERDR)) { return $env:WTW_HERDR }

    $cmd = Get-Command herdr -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    $exeName = if ($IsWindows) { 'herdr.exe' } else { 'herdr' }
    $homeDir = if ($HOME) { $HOME } else { $env:USERPROFILE }
    if ($homeDir) {
        # install.sh and the release binaries land in ~/.local/bin; cargo in ~/.cargo/bin.
        foreach ($dir in @('.local/bin', '.cargo/bin')) {
            $candidate = Join-Path (Join-Path $homeDir $dir) $exeName
            if (Test-Path $candidate) { return $candidate }
        }
    }

    return $null
}

function Invoke-WtwHerdrCommand {
    <#
    .SYNOPSIS
        Run a herdr CLI command and parse its JSON reply. Result has ExitCode,
        Result (the reply's .result), ErrorCode and Output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $ArgumentList
    )

    $exe = Get-WtwHerdrExe
    if (-not $exe) {
        return [PSCustomObject]@{ ExitCode = 127; Result = $null; ErrorCode = 'not_found'; Output = 'herdr not found' }
    }

    Write-Verbose "herdr command: $exe $($ArgumentList -join ' ')"
    $output = & $exe @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) { $exitCode = 0 }
    $text = ((@($output) | ForEach-Object { "$_" }) -join [Environment]::NewLine).Trim()

    $reply = $null
    $jsonLine = @($text -split '\r?\n' | Where-Object { $_.TrimStart().StartsWith('{') }) | Select-Object -Last 1
    if ($jsonLine) {
        try { $reply = $jsonLine | ConvertFrom-Json -Depth 20 -ErrorAction Stop } catch { $reply = $null }
    }

    $errorCode = $null
    if ($reply -and $reply.PSObject.Properties['error'] -and $reply.error) {
        $errorCode = "$($reply.error.code)"
        if ($exitCode -eq 0) { $exitCode = 1 }
        if ($reply.error.message) { $text = "$($reply.error.message)" }
    }
    $result = if ($reply -and $reply.PSObject.Properties['result']) { $reply.result } else { $null }

    return [PSCustomObject]@{ ExitCode = $exitCode; Result = $result; ErrorCode = $errorCode; Output = $text }
}

function Find-WtwHerdrWorkspace {
    <#
    .SYNOPSIS
        Find the herdr workspace with a pane rooted at the target directory,
        falling back to a workspace labelled with the pretty name.
    #>
    [CmdletBinding()]
    param(
        [string] $PrettyName,
        [string] $ProjectPath
    )

    if ($ProjectPath) {
        $panes = Invoke-WtwHerdrCommand -ArgumentList @('pane', 'list')
        if ($panes.ExitCode -eq 0 -and $panes.Result) {
            $fullPath = [System.IO.Path]::GetFullPath($ProjectPath).TrimEnd('/', '\')
            $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
            foreach ($pane in @($panes.Result.panes)) {
                if (-not $pane.cwd) { continue }
                $panePath = [System.IO.Path]::GetFullPath("$($pane.cwd)").TrimEnd('/', '\')
                if ([string]::Equals($panePath, $fullPath, $comparison)) { return "$($pane.workspace_id)" }
            }
        }
    }

    if (-not $PrettyName) { return $null }
    $list = Invoke-WtwHerdrCommand -ArgumentList @('workspace', 'list')
    if ($list.ExitCode -ne 0 -or -not $list.Result) { return $null }
    foreach ($workspace in @($list.Result.workspaces)) {
        if ([string]::Equals("$($workspace.label)", $PrettyName, [StringComparison]::Ordinal)) {
            return "$($workspace.workspace_id)"
        }
    }

    return $null
}

function Start-WtwHerdrServer {
    <#
    .SYNOPSIS
        Launch herdr in a new Ghostty window at the target and wait for its
        server socket. Returns $true once `herdr workspace list` answers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [int] $TimeoutSeconds = 10
    )

    if (-not (Start-WtwGhosttyWindow -WorkingDirectory $ProjectPath -Command @(Get-WtwHerdrExe))) { return $false }

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 250
        if ((Invoke-WtwHerdrCommand -ArgumentList @('workspace', 'list')).ExitCode -eq 0) { return $true }
    }
    return $false
}

function Open-WtwHerdrProject {
    <#
    .SYNOPSIS
        Open a wtw target as a herdr workspace: focus (and relabel) the one
        already rooted at the target, otherwise create one there.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName
    )

    if (-not (Get-WtwHerdrExe)) {
        return [PSCustomObject]@{ Success = $false; Created = $false; Started = $false; Reason = 'herdr not found' }
    }

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $started = $false
    $probe = Invoke-WtwHerdrCommand -ArgumentList @('workspace', 'list')
    if ($probe.ErrorCode -eq 'server_not_running') {
        if (-not (Start-WtwHerdrServer -ProjectPath $fullPath)) {
            return [PSCustomObject]@{
                Success = $false; Created = $false; Started = $false; Path = $fullPath
                Reason  = 'no herdr server is running and Ghostty could not start one. Run `herdr` in a terminal, then retry.'
            }
        }
        $started = $true
    } elseif ($probe.ExitCode -ne 0) {
        return [PSCustomObject]@{ Success = $false; Created = $false; Started = $false; Path = $fullPath; Reason = $probe.Output }
    }

    # A fresh server opens its first workspace at the launch dir, so this also
    # picks that one up and gives it the wtw label.
    $workspaceId = Find-WtwHerdrWorkspace -PrettyName $PrettyName -ProjectPath $fullPath
    if ($workspaceId) {
        Invoke-WtwHerdrCommand -ArgumentList @('workspace', 'rename', $workspaceId, $PrettyName) | Out-Null
        Invoke-WtwHerdrCommand -ArgumentList @('workspace', 'focus', $workspaceId) | Out-Null
        return [PSCustomObject]@{
            Success = $true; Created = $started; Started = $started; Path = $fullPath; Id = $workspaceId; Reason = $null
        }
    }

    $result = Invoke-WtwHerdrCommand -ArgumentList @('workspace', 'create', '--cwd', $fullPath, '--label', $PrettyName, '--focus')
    if ($result.ExitCode -ne 0) {
        return [PSCustomObject]@{ Success = $false; Created = $false; Started = $started; Path = $fullPath; Reason = $result.Output }
    }

    $workspaceId = if ($result.Result -and $result.Result.workspace) { "$($result.Result.workspace.workspace_id)" } else { $null }
    return [PSCustomObject]@{
        Success = $true; Created = $true; Started = $started; Path = $fullPath; Id = $workspaceId; Reason = $null
    }
}
