# wmux integration for wtw.
#
# wmux (https://github.com/amirlehmam/wmux) is a Windows terminal multiplexer.
# It ships a Node-based JSON-RPC CLI under `<install>/resources/cli/wmux.js`
# that talks to the running app over a named pipe. The supported surface used
# here:
#   wmux new-workspace --title <name> --cwd <path> [--shell <pwsh>]  -> {workspaceId}
#   wmux list-workspaces                                             -> {workspaces:[{id,title,cwd,...}]}
#   wmux select-workspace <id>                                       -> {ok:true}
#   wmux close-workspace  <id>                                       -> {ok:true}
#   wmux ping                                                        -> pong
#
# This mirrors what cmux does on macOS (Register/Open/Unregister a project), but
# wmux workspaces are live (daemon-backed) rather than a static config registry,
# so "registration" means creating the workspace in a running wmux.

function Get-WtwWmuxExe {
    [CmdletBinding()]
    param()

    # Explicit override wins.
    if ($env:WMUX_EXE -and (Test-Path $env:WMUX_EXE)) { return $env:WMUX_EXE }

    # Prefer an install that actually ships the bundled Node CLI wtw drives
    # (resources/cli/wmux.js) — there can be multiple wmux builds on a machine
    # (e.g. a Squirrel install under %LOCALAPPDATA%\WMUX that packages its CLI
    # differently). Fall back to the first existing exe so Start-WtwWmuxApp can
    # still try to launch something.
    $first = $null
    foreach ($exe in (Get-WtwWmuxExeCandidate)) {
        if (-not (Test-Path $exe)) { continue }
        if (-not $first) { $first = $exe }
        if (Resolve-WtwWmuxCliForExe -Exe $exe) { return $exe }
    }

    return $first
}

function Get-WtwWmuxExeCandidate {
    <#
    .SYNOPSIS
        Ordered list of candidate wmux.exe paths (not filtered by existence).
    #>
    [CmdletBinding()]
    param()

    $candidates = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $add = {
        param($p)
        if ($p -and $seen.Add($p)) { $candidates.Add($p) }
    }

    if ($env:WMUX_EXE) { & $add $env:WMUX_EXE }

    # A running wmux tells us exactly where it was installed. Verify the image
    # path still exists in case the install was moved/renamed while running.
    $proc = Get-Process -Name wmux -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and (Test-Path $_.Path) } | Select-Object -First 1
    if ($proc) { & $add $proc.Path }

    $cmd = Get-Command wmux.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { & $add $cmd.Source }

    if (-not $IsWindows) { return $candidates }

    # Folder layouts wmux is commonly dropped into (it ships without an
    # installer, so users place it wherever, e.g. E:\ProgramFilesFolder\WMUX).
    $relativeDirs = @(
        'WMUX',
        'wmux',
        'ProgramFilesFolder/WMUX',
        'Program Files/WMUX',
        'Program Files (x86)/WMUX',
        'ProgramFiles/WMUX',
        'Programs/WMUX'
    )

    # Env-derived well-known roots first (fast, most likely).
    foreach ($root in @(
            (Join-Path $env:LOCALAPPDATA 'Programs'),
            $env:LOCALAPPDATA,
            $env:ProgramFiles,
            ${env:ProgramFiles(x86)},
            $env:ProgramW6432)) {
        if ($root) {
            & $add (Join-Path $root 'WMUX/wmux.exe')
            & $add (Join-Path $root 'wmux/wmux.exe')
        }
    }

    # Sweep attached drives (fixed + removable) with the common folder layouts.
    try {
        $driveRoots = [System.IO.DriveInfo]::GetDrives() |
            Where-Object { $_.IsReady -and ($_.DriveType.ToString() -in @('Fixed', 'Removable')) } |
            ForEach-Object { $_.RootDirectory.FullName }
    } catch {
        $driveRoots = @()
    }
    foreach ($drive in $driveRoots) {
        foreach ($rel in $relativeDirs) {
            & $add (Join-Path $drive (Join-Path $rel 'wmux.exe'))
        }
    }

    return $candidates
}

function Resolve-WtwWmuxCliForExe {
    <#
    .SYNOPSIS
        Resolve the bundled Node CLI (resources/cli/wmux.js) for a wmux.exe, or
        $null if that install doesn't ship it in the layout wtw supports.
    #>
    [CmdletBinding()]
    param([string] $Exe)

    if (-not $Exe) { return $null }
    $dir = Split-Path $Exe -Parent
    if (-not $dir) { return $null }

    # Portable layout: resources/cli/wmux.js next to wmux.exe.
    $direct = Join-Path $dir 'resources/cli/wmux.js'
    if (Test-Path $direct) { return $direct }

    # Squirrel layout: <dir>\app-<version>\resources\cli\wmux.js (newest first).
    $appDirs = Get-ChildItem -Path $dir -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    foreach ($appDir in $appDirs) {
        $nested = Join-Path $appDir.FullName 'resources/cli/wmux.js'
        if (Test-Path $nested) { return $nested }
    }

    return $null
}

function Get-WtwWmuxCliScript {
    [CmdletBinding()]
    param()

    # wmux sets WMUX_CLI inside the shells it spawns; honor it when present.
    if ($env:WMUX_CLI -and (Test-Path $env:WMUX_CLI)) { return $env:WMUX_CLI }

    foreach ($exe in (Get-WtwWmuxExeCandidate)) {
        if (-not (Test-Path $exe)) { continue }
        $cli = Resolve-WtwWmuxCliForExe -Exe $exe
        if ($cli) { return $cli }
    }

    return $null
}

function Get-WtwWmuxNode {
    [CmdletBinding()]
    param()

    if ($env:WMUX_NODE -and (Test-Path $env:WMUX_NODE)) { return $env:WMUX_NODE }

    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    return $null
}

function Get-WtwWmuxInvoker {
    <#
    .SYNOPSIS
        Resolve how to run the wmux CLI.
    .DESCRIPTION
        Returns an object @{ Exe; Prefix } where invoking `& $Exe @Prefix @args`
        runs the wmux CLI. Preferred shape is `node <wmux.js>`; falls back to a
        `wmux` command on PATH if it is a real executable/script shim. Returns
        $null when no usable CLI can be found.
    #>
    [CmdletBinding()]
    param()

    $script = Get-WtwWmuxCliScript
    if ($script) {
        $node = Get-WtwWmuxNode
        if ($node) { return [PSCustomObject]@{ Exe = $node; Prefix = @($script) } }
    }

    $cmd = Get-Command wmux -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.CommandType -in @('Application', 'ExternalScript') -and $cmd.Source) {
        return [PSCustomObject]@{ Exe = $cmd.Source; Prefix = @() }
    }

    return $null
}

function Test-WtwWmuxPresent {
    [CmdletBinding()]
    param()

    return [bool](Get-WtwWmuxInvoker)
}

function Invoke-WtwWmuxCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $ArgumentList
    )

    $invoker = Get-WtwWmuxInvoker
    if (-not $invoker) {
        return [PSCustomObject]@{ ExitCode = 127; Output = 'wmux CLI not found' }
    }

    $allArgs = @($invoker.Prefix) + $ArgumentList
    Write-Verbose "wmux command: $($invoker.Exe) $($allArgs -join ' ')"
    $output = & $invoker.Exe @allArgs 2>&1
    $outputText = $output -join [Environment]::NewLine
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) { $exitCode = 0 }

    return [PSCustomObject]@{ ExitCode = $exitCode; Output = $outputText }
}

function ConvertFrom-WtwWmuxJsonOutput {
    [CmdletBinding()]
    param([string] $Output)

    if ([string]::IsNullOrWhiteSpace($Output)) { return $null }
    try {
        return $Output | ConvertFrom-Json -Depth 100 -ErrorAction Stop
    } catch {
        return $null
    }
}

function Get-WtwWmuxObjectValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)][string[]] $Names
    )

    foreach ($name in $Names) {
        $prop = $Object.PSObject.Properties[$name]
        if ($prop -and $null -ne $prop.Value -and "$($prop.Value)" -ne '') {
            return $prop.Value
        }
    }

    return $null
}

function Test-WtwWmuxRunning {
    [CmdletBinding()]
    param()

    if (-not (Test-WtwWmuxPresent)) { return $false }
    $result = Invoke-WtwWmuxCommand -ArgumentList @('ping')
    return ($result.ExitCode -eq 0 -and $result.Output -match 'pong')
}

function Start-WtwWmuxApp {
    <#
    .SYNOPSIS
        Launch the wmux app and wait (briefly) for its CLI pipe to come up.
    #>
    [CmdletBinding()]
    param([int] $TimeoutSeconds = 12)

    $exe = Get-WtwWmuxExe
    if (-not $exe) { return $false }

    try {
        Start-Process -FilePath $exe | Out-Null
    } catch {
        return $false
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        if (Test-WtwWmuxRunning) { return $true }
    }

    return (Test-WtwWmuxRunning)
}

function Confirm-WtwWmuxRunning {
    <#
    .SYNOPSIS
        Ensure wmux is running, starting it when necessary.
    #>
    [CmdletBinding()]
    param([switch] $StartIfStopped)

    if (Test-WtwWmuxRunning) { return $true }
    if (-not $StartIfStopped) { return $false }
    return (Start-WtwWmuxApp)
}

function Get-WtwWmuxShell {
    <#
    .SYNOPSIS
        Preferred shell for new wmux surfaces (pwsh, to match wtw's PS7 base).
        Returns $null to let wmux fall back to its configured default shell.
    #>
    [CmdletBinding()]
    param()

    $cmd = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    return $null
}

function Get-WtwWmuxLiveWorkspaces {
    [CmdletBinding()]
    param()

    $result = Invoke-WtwWmuxCommand -ArgumentList @('list-workspaces')
    if ($result.ExitCode -ne 0) { return @() }

    $parsed = ConvertFrom-WtwWmuxJsonOutput -Output $result.Output
    if (-not $parsed) { return @() }
    if ($parsed.PSObject.Properties.Name -contains 'workspaces') { return @($parsed.workspaces) }
    if ($parsed -is [array]) { return @($parsed) }
    return @($parsed)
}

function Find-WtwWmuxWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $PrettyName)

    foreach ($ws in (Get-WtwWmuxLiveWorkspaces)) {
        $name = Get-WtwWmuxObjectValue -Object $ws -Names @('title', 'name', 'displayName')
        if ([string]::Equals($name, $PrettyName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $ws
        }
    }

    return $null
}

function New-WtwWmuxWorkspace {
    <#
    .SYNOPSIS
        Create a wmux workspace rooted at a directory. Assumes wmux is running.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName
    )

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $argList = @('new-workspace', '--title', $PrettyName, '--cwd', $fullPath)

    $shell = Get-WtwWmuxShell
    if ($shell) { $argList += @('--shell', $shell) }

    $result = Invoke-WtwWmuxCommand -ArgumentList $argList
    if ($result.ExitCode -ne 0) {
        return [PSCustomObject]@{ Success = $false; Id = $null; Reason = $result.Output }
    }

    $parsed = ConvertFrom-WtwWmuxJsonOutput -Output $result.Output
    $id = if ($parsed) { Get-WtwWmuxObjectValue -Object $parsed -Names @('workspaceId', 'id') } else { $null }

    return [PSCustomObject]@{ Success = $true; Id = $id; Reason = $null }
}

function Open-WtwWmuxProject {
    <#
    .SYNOPSIS
        Open a wtw target as a wmux workspace: reuse a same-named workspace if one
        exists, otherwise create it. Starts wmux when it is not already running.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName,
        [string] $StatusValue
    )

    if (-not $IsWindows) {
        return [PSCustomObject]@{ Success = $false; Reason = 'wmux is Windows-only' }
    }
    if (-not (Test-WtwWmuxPresent)) {
        return [PSCustomObject]@{ Success = $false; Reason = 'wmux CLI not found' }
    }

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)

    if (-not (Confirm-WtwWmuxRunning -StartIfStopped)) {
        return [PSCustomObject]@{
            Success       = $false
            Created       = $false
            WorkspaceName = $PrettyName
            Path          = $fullPath
            Reason        = 'wmux is not running and could not be started.'
        }
    }

    $existing = Find-WtwWmuxWorkspace -PrettyName $PrettyName
    if ($existing) {
        $wsId = Get-WtwWmuxObjectValue -Object $existing -Names @('id', 'workspaceId', 'ref')
        if ($wsId) { Invoke-WtwWmuxCommand -ArgumentList @('select-workspace', "$wsId") | Out-Null }
        return [PSCustomObject]@{
            Success = $true; Created = $false; WorkspaceName = $PrettyName; Path = $fullPath; Id = $wsId; Reason = $null
        }
    }

    $created = New-WtwWmuxWorkspace -ProjectPath $fullPath -PrettyName $PrettyName
    if (-not $created.Success) {
        return [PSCustomObject]@{
            Success = $false; Created = $false; WorkspaceName = $PrettyName; Path = $fullPath; Reason = $created.Reason
        }
    }

    if ($created.Id) { Invoke-WtwWmuxCommand -ArgumentList @('select-workspace', "$($created.Id)") | Out-Null }
    return [PSCustomObject]@{
        Success = $true; Created = $true; WorkspaceName = $PrettyName; Path = $fullPath; Id = $created.Id; Reason = $null
    }
}

function Register-WtwWmuxProject {
    <#
    .SYNOPSIS
        Create a wmux workspace for a worktree (called by `wtw add` / `wtw create`).
    .DESCRIPTION
        wmux has no static SourceGit-style on-disk repository registry; its
        workspaces are live. So registration here means creating the workspace in
        a running wmux (starting wmux if needed). Best-effort: never blocks
        worktree setup. Returns the workspace title (stored as wmuxWorkspaceName)
        so it can be found/closed later, or $null when nothing was created.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName,
        [string] $RepoName,
        [string] $TaskName
    )

    if (-not $IsWindows) { return $null }
    if (-not (Test-WtwWmuxPresent)) {
        Write-Host '  wmux: CLI not found - skipping workspace creation.' -ForegroundColor DarkGray
        return $null
    }

    if (-not (Confirm-WtwWmuxRunning -StartIfStopped)) {
        $hint = if ($TaskName) { "wtw wmux $TaskName" } else { 'wtw wmux <name>' }
        Write-Host "  wmux: app not running - skipped. Run '$hint' to create the workspace once wmux is open." -ForegroundColor DarkGray
        return $null
    }

    $existing = Find-WtwWmuxWorkspace -PrettyName $PrettyName
    if ($existing) {
        Write-Host "  wmux: workspace already exists '$PrettyName'." -ForegroundColor DarkGray
        return $PrettyName
    }

    $created = New-WtwWmuxWorkspace -ProjectPath $ProjectPath -PrettyName $PrettyName
    if (-not $created.Success) {
        Write-Host "  wmux: could not create workspace - $($created.Reason)" -ForegroundColor Yellow
        return $null
    }

    Write-Host "  wmux: created workspace '$PrettyName'" -ForegroundColor Green
    return $PrettyName
}

function Unregister-WtwWmuxProject {
    <#
    .SYNOPSIS
        Close the wmux workspace created for a worktree (called by `wtw remove`).
    #>
    [CmdletBinding()]
    param([string] $PrettyName)

    if (-not $IsWindows) { return }
    if (-not $PrettyName) { return }
    if (-not (Test-WtwWmuxPresent)) { return }
    if (-not (Test-WtwWmuxRunning)) { return }

    $workspace = Find-WtwWmuxWorkspace -PrettyName $PrettyName
    if (-not $workspace) { return }

    $workspaceId = Get-WtwWmuxObjectValue -Object $workspace -Names @('id', 'workspaceId', 'ref')
    if (-not $workspaceId) { return }

    $result = Invoke-WtwWmuxCommand -ArgumentList @('close-workspace', "$workspaceId")
    if ($result.ExitCode -eq 0) {
        Write-Host "  wmux: closed workspace '$PrettyName'." -ForegroundColor Green
    }
}
