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

    $cmd = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    return $null
}

function Test-WtwWmuxElectronNode {
    <#
    .SYNOPSIS
        True when $Path is wmux's Electron binary used as Node (ELECTRON_RUN_AS_NODE).
    #>
    [CmdletBinding()]
    param([string] $Path)

    if (-not $Path) { return $false }
    if ($env:WMUX_NODE_ELECTRON) { return $true }
    return ([System.IO.Path]::GetFileName($Path) -eq 'wmux.exe')
}

function Get-WtwWmuxInvoker {
    <#
    .SYNOPSIS
        Resolve how to run the wmux CLI.
    .DESCRIPTION
        Returns an object @{ Exe; Prefix; ElectronAsNode } where invoking
        `& $Exe @Prefix @args` runs the wmux JSON-RPC CLI. Preferred shape is
        `node <wmux.js>`. When standalone Node is missing, the same `wmux.js` is
        run via wmux.exe with ELECTRON_RUN_AS_NODE — that is what wmux's own
        cmd/ps1 shims do. Never fall back to launching wmux.exe as a GUI with
        CLI args: `wmux.exe ping` starts the app instead of talking to the pipe.
    #>
    [CmdletBinding()]
    param()

    $script = Get-WtwWmuxCliScript
    if ($script) {
        $node = Get-WtwWmuxNode
        if ($node) {
            return [PSCustomObject]@{
                Exe            = $node
                Prefix         = @($script)
                ElectronAsNode = [bool](Test-WtwWmuxElectronNode -Path $node)
            }
        }

        $exe = Get-WtwWmuxExe
        if ($exe) {
            return [PSCustomObject]@{
                Exe            = $exe
                Prefix         = @($script)
                ElectronAsNode = $true
            }
        }
    }

    # PowerShell shim (wmux.ps1) wraps node/wmux.js. The GUI exe must not be
    # used here — CommandType Application is almost always wmux.exe.
    $cmd = Get-Command wmux -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.CommandType -eq 'ExternalScript' -and $cmd.Source) {
        return [PSCustomObject]@{ Exe = $cmd.Source; Prefix = @(); ElectronAsNode = $false }
    }

    return $null
}

function Test-WtwWmuxPresent {
    [CmdletBinding()]
    param()

    return [bool](Get-WtwWmuxInvoker)
}

function Restore-WtwEnvVar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Name,
        [AllowNull()][AllowEmptyString()][string] $Previous
    )

    if ($null -eq $Previous -or $Previous -eq '') {
        Remove-Item "Env:$Name" -ErrorAction SilentlyContinue
    } else {
        Set-Item -Path "Env:$Name" -Value $Previous
    }
}

function ConvertTo-WtwWmuxCliOutput {
    <#
    .SYNOPSIS
        Flatten native stdout/stderr and drop packaged-Electron NODE_OPTIONS noise.
    #>
    [CmdletBinding()]
    param($Raw)

    $chunks = foreach ($item in @($Raw)) {
        if ($null -eq $item) { continue }
        if ($item -is [System.Management.Automation.ErrorRecord]) { $item.ToString() }
        else { "$item" }
    }
    $text = $chunks -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }

    $kept = foreach ($line in ($text -split '\r?\n')) {
        if ($line -match 'NODE_OPTIONS are not supported in packaged apps') { continue }
        if ($line -match 'ERROR:electron\\shell\\common\\node_bindings') { continue }
        $line
    }
    return ($kept -join [Environment]::NewLine).Trim()
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

    $previousElectron = $env:ELECTRON_RUN_AS_NODE
    $previousNodeOptions = $env:NODE_OPTIONS
    $previousNative = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ValueOnly -ErrorAction SilentlyContinue
    try {
        if ($invoker.ElectronAsNode) {
            $env:ELECTRON_RUN_AS_NODE = '1'
            # Packaged Electron logs (and can fail) when NODE_OPTIONS is set —
            # jax/pnpm leave ``--max-old-space-size`` on the interactive shell.
            Remove-Item Env:NODE_OPTIONS -ErrorAction SilentlyContinue
        }
        if ($null -ne $previousNative) { $PSNativeCommandUseErrorActionPreference = $false }
        $raw = & $invoker.Exe @allArgs 2>&1
        $outputText = ConvertTo-WtwWmuxCliOutput -Raw $raw
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = 0 }
        return [PSCustomObject]@{ ExitCode = $exitCode; Output = $outputText }
    } catch {
        return [PSCustomObject]@{ ExitCode = 1; Output = "$($_.Exception.Message)" }
    } finally {
        if ($null -ne $previousNative) { $PSNativeCommandUseErrorActionPreference = $previousNative }
        Restore-WtwEnvVar -Name 'ELECTRON_RUN_AS_NODE' -Previous $previousElectron
        Restore-WtwEnvVar -Name 'NODE_OPTIONS' -Previous $previousNodeOptions
    }
}

function ConvertFrom-WtwWmuxJsonOutput {
    [CmdletBinding()]
    param([string] $Output)

    if ([string]::IsNullOrWhiteSpace($Output)) { return $null }

    $candidates = [System.Collections.Generic.List[string]]::new()
    $candidates.Add($Output) | Out-Null
    foreach ($line in ($Output -split '\r?\n')) {
        $trim = $line.Trim()
        if ($trim.StartsWith('{') -or $trim.StartsWith('[')) {
            $candidates.Add($trim) | Out-Null
        }
    }

    for ($i = $candidates.Count - 1; $i -ge 0; $i--) {
        try {
            return $candidates[$i] | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        } catch {
            continue
        }
    }

    return $null
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
        Launch the wmux app and wait for its CLI pipe to come up.
    .DESCRIPTION
        Cold start installs Claude hooks and checks for updates before the
        named pipe answers `ping`. 12s was too short: the app would come up,
        wtw would give up, and the user would see the GUI logs followed by
        "wmux is not running and could not be started."
    #>
    [CmdletBinding()]
    param([int] $TimeoutSeconds = 45)

    $exe = Get-WtwWmuxExe
    if (-not $exe) { return $false }

    $previousElectron = $env:ELECTRON_RUN_AS_NODE
    $previousNodeOptions = $env:NODE_OPTIONS
    try {
        # GUI launch must not inherit ELECTRON_RUN_AS_NODE from a prior CLI call,
        # or jax/pnpm NODE_OPTIONS (packaged Electron logs that as a hard error).
        Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
        Remove-Item Env:NODE_OPTIONS -ErrorAction SilentlyContinue
        # UseShellExecute detaches from this console so packaged-Electron logs
        # do not spill into the parent pwsh / Starship prompt.
        $psi = [System.Diagnostics.ProcessStartInfo]::new($exe)
        $psi.UseShellExecute = $true
        $exeDir = Split-Path -Parent $exe
        if ($exeDir) { $psi.WorkingDirectory = $exeDir }
        [void][System.Diagnostics.Process]::Start($psi)
    } catch {
        return $false
    } finally {
        Restore-WtwEnvVar -Name 'ELECTRON_RUN_AS_NODE' -Previous $previousElectron
        Restore-WtwEnvVar -Name 'NODE_OPTIONS' -Previous $previousNodeOptions
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
        Check that wmux is running. With -StartIfStopped, launch it.
    .DESCRIPTION
        Only `wtw wmux` passes -StartIfStopped. `wtw create` / `wtw add` must
        not auto-start the GUI — they skip live workspace creation instead.
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
    if ((Get-WtwPropertyNames -Object $parsed) -contains 'workspaces') { return @($parsed.workspaces) }
    if ($parsed -is [array]) { return @($parsed) }
    return @($parsed)
}

function Find-WtwWmuxWorkspace {
    [CmdletBinding()]
    param(
        [string] $PrettyName,
        [string] $ProjectPath
    )

    $workspaces = @(Get-WtwWmuxLiveWorkspaces)
    if ($ProjectPath) {
        $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)
        $byCwd = $workspaces | Where-Object {
            $cwd = Get-WtwWmuxObjectValue -Object $_ -Names @('cwd', 'path', 'workingDirectory')
            $cwd -and [string]::Equals(
                [System.IO.Path]::GetFullPath("$cwd"),
                $fullPath,
                [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1
        if ($byCwd) { return $byCwd }
    }

    if (-not $PrettyName) { return $null }

    foreach ($ws in $workspaces) {
        $name = Get-WtwWmuxObjectValue -Object $ws -Names @('title', 'name', 'displayName')
        if ([string]::Equals($name, $PrettyName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $ws
        }
    }

    return $null
}

function Get-WtwWmuxWorkspaceId {
    [CmdletBinding()]
    param($Workspace)

    if (-not $Workspace) { return $null }
    return Get-WtwWmuxObjectValue -Object $Workspace -Names @('id', 'workspaceId', 'ref')
}

function Sync-WtwWmuxWorkspaceTitle {
    <#
    .SYNOPSIS
        Rename a live wmux workspace when the cwd-matched title is stale.
    .DESCRIPTION
        Matching is by cwd first so a title change (emoji, humanized spaces)
        does not duplicate the tab. cmux already renames; wmux needs this.
    #>
    [CmdletBinding()]
    param(
        $Workspace,
        [string] $PrettyName
    )

    if (-not $Workspace -or [string]::IsNullOrWhiteSpace($PrettyName)) { return }
    $id = Get-WtwWmuxWorkspaceId -Workspace $Workspace
    if (-not $id) { return }

    $current = Get-WtwWmuxObjectValue -Object $Workspace -Names @('title', 'name', 'displayName')
    if ([string]::Equals("$current", $PrettyName, [System.StringComparison]::Ordinal)) { return }

    Invoke-WtwWmuxCommand -ArgumentList @('rename-workspace', "$id", $PrettyName) | Out-Null
}

function Select-WtwWmuxWorkspace {
    [CmdletBinding()]
    param($Workspace)

    $id = Get-WtwWmuxWorkspaceId -Workspace $Workspace
    if (-not $id) { return $null }
    Invoke-WtwWmuxCommand -ArgumentList @('select-workspace', "$id") | Out-Null
    return $id
}

function Save-WtwWmuxWorkspaceName {
    [CmdletBinding()]
    param(
        [psobject] $Target,
        [string] $WorkspaceName
    )

    if (-not $Target -or [string]::IsNullOrWhiteSpace($WorkspaceName)) { return }
    $repoName = Get-WtwPropertyValue -Object $Target -Name 'RepoName'
    $taskName = Get-WtwPropertyValue -Object $Target -Name 'TaskName'
    if (-not $repoName -or -not $taskName) { return }

    $registry = Get-WtwRegistry
    if (-not $registry -or -not $registry.repos) { return }
    if ((Get-WtwPropertyNames -Object $registry.repos) -notcontains $repoName) { return }
    $repo = $registry.repos.$repoName
    $worktrees = Get-WtwPropertyValue -Object $repo -Name 'worktrees'
    if (-not $worktrees) { return }
    if ((Get-WtwPropertyNames -Object $worktrees) -notcontains $taskName) { return }

    $wt = $worktrees.$taskName
    $wt | Add-Member -NotePropertyName 'wmuxWorkspaceName' -NotePropertyValue $WorkspaceName -Force
    Save-WtwRegistry $registry
}

function Complete-WtwWmuxWorkspace {
    <#
    .SYNOPSIS
        Rename to the pretty title and select so the tab is visible.
    #>
    [CmdletBinding()]
    param(
        [string] $PrettyName,
        [string] $ProjectPath,
        $Workspace
    )

    $live = $Workspace
    if (-not $live) {
        $live = Find-WtwWmuxWorkspace -PrettyName $PrettyName -ProjectPath $ProjectPath
    }
    if (-not $live) { return $null }

    Sync-WtwWmuxWorkspaceTitle -Workspace $live -PrettyName $PrettyName
    return (Select-WtwWmuxWorkspace -Workspace $live)
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

    $existing = Find-WtwWmuxWorkspace -PrettyName $PrettyName -ProjectPath $fullPath
    if ($existing) {
        $wsId = Complete-WtwWmuxWorkspace -PrettyName $PrettyName -ProjectPath $fullPath -Workspace $existing
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

    $wsId = Complete-WtwWmuxWorkspace -PrettyName $PrettyName -ProjectPath $fullPath
    if (-not $wsId -and $created.Id) {
        Invoke-WtwWmuxCommand -ArgumentList @('select-workspace', "$($created.Id)") | Out-Null
        $wsId = $created.Id
    }

    return [PSCustomObject]@{
        Success = $true; Created = $true; WorkspaceName = $PrettyName; Path = $fullPath; Id = $wsId; Reason = $null
    }
}

function Register-WtwWmuxProject {
    <#
    .SYNOPSIS
        Create a wmux workspace for a worktree (called by `wtw add` / `wtw create`).
    .DESCRIPTION
        wmux has no static SourceGit-style on-disk repository registry; its
        workspaces are live. Registration here means creating the workspace in
        an already-running wmux. It does not start the app — that is reserved
        for the explicit `wtw wmux` command. Best-effort: never blocks worktree
        setup. Returns the workspace title (stored as wmuxWorkspaceName) so it
        can be found/closed later, or $null when nothing was created.
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

    if (-not (Confirm-WtwWmuxRunning)) {
        $hint = if ($TaskName) { "wtw wmux $TaskName" } else { 'wtw wmux <name>' }
        Write-Host "  wmux: app not running - skipped. Run '$hint' to create the workspace once wmux is open." -ForegroundColor DarkGray
        return $null
    }

    $existing = Find-WtwWmuxWorkspace -PrettyName $PrettyName -ProjectPath $ProjectPath
    if ($existing) {
        Complete-WtwWmuxWorkspace -PrettyName $PrettyName -ProjectPath $ProjectPath -Workspace $existing | Out-Null
        Write-Host "  wmux: workspace already exists '$PrettyName'." -ForegroundColor DarkGray
        return $PrettyName
    }

    $created = New-WtwWmuxWorkspace -ProjectPath $ProjectPath -PrettyName $PrettyName
    if (-not $created.Success) {
        Write-Host "  wmux: could not create workspace - $($created.Reason)" -ForegroundColor Yellow
        return $null
    }

    Complete-WtwWmuxWorkspace -PrettyName $PrettyName -ProjectPath $ProjectPath | Out-Null
    Write-Host "  wmux: created workspace '$PrettyName'" -ForegroundColor Green
    return $PrettyName
}

function Unregister-WtwWmuxProject {
    <#
    .SYNOPSIS
        Close the wmux workspace created for a worktree (called by `wtw remove`).
    #>
    [CmdletBinding()]
    param(
        [string] $PrettyName,
        [string] $ProjectPath
    )

    if (-not $IsWindows) { return }
    if (-not $PrettyName -and -not $ProjectPath) { return }
    if (-not (Test-WtwWmuxPresent)) { return }
    if (-not (Test-WtwWmuxRunning)) { return }

    $workspace = Find-WtwWmuxWorkspace -PrettyName $PrettyName -ProjectPath $ProjectPath
    if (-not $workspace) { return }

    $workspaceId = Get-WtwWmuxObjectValue -Object $workspace -Names @('id', 'workspaceId', 'ref')
    if (-not $workspaceId) { return }

    $result = Invoke-WtwWmuxCommand -ArgumentList @('close-workspace', "$workspaceId")
    if ($result.ExitCode -eq 0) {
        Write-Host "  wmux: closed workspace '$PrettyName'." -ForegroundColor Green
    }
}
