# Wave Terminal integration for wtw.
#
# Wave (https://waveterm.dev) ships `wsh`, a CLI that talks to the running app
# over the RPC token Wave injects into its own shells (WAVETERM_JWT /
# WAVETERM_SWAPTOKEN, plus WAVETERM_TABID / WAVETERM_BLOCKID). The supported
# surface used here:
#   wsh term <dir>                         -> "terminal block created: block:<uuid>"
#   wsh blocks list --tab <id> --json      -> [{blockid,tabid,view,meta:{cmd:cwd,...}}]
#   wsh setmeta -b <block> key=value ...   -> frame:title / frame:bordercolor
#   wsh focusblock -b <block>
#
# wsh has no "new workspace" or "new tab" command, and it only works from a
# shell Wave itself spawned. So unlike cmux/wmux, a wtw target maps to a
# terminal block in the current Wave tab: reuse the block already rooted at
# the target, otherwise split a new one there.

function Get-WtwWshExe {
    [CmdletBinding()]
    param()

    if ($env:WTW_WSH -and (Test-Path $env:WTW_WSH)) { return $env:WTW_WSH }

    $cmd = Get-Command wsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    $exeName = if ($IsWindows) { 'wsh.exe' } else { 'wsh' }
    $dirs = [System.Collections.Generic.List[string]]::new()
    # Wave sets this inside its shells, even when PATH was rewritten by a profile.
    if ($env:WAVETERM_WSHBINDIR) { $dirs.Add($env:WAVETERM_WSHBINDIR) }
    $homeDir = if ($HOME) { $HOME } else { $env:USERPROFILE }
    if ($homeDir) {
        $dirs.Add((Join-Path $homeDir '.waveterm/bin'))
        $dirs.Add((Join-Path $homeDir '.local/share/waveterm/bin'))
        # Snap (classic) keeps its data dir under ~/snap/waveterm/<rev>.
        $dirs.Add((Join-Path $homeDir 'snap/waveterm/current/.local/share/waveterm/bin'))
        $dirs.Add((Join-Path $homeDir 'Library/Application Support/waveterm/bin'))
    }
    if ($env:LOCALAPPDATA) { $dirs.Add((Join-Path $env:LOCALAPPDATA 'waveterm/bin')) }

    foreach ($dir in $dirs) {
        $candidate = Join-Path $dir $exeName
        if (Test-Path $candidate) { return $candidate }
    }

    return $null
}

function Test-WtwWaveSession {
    <#
    .SYNOPSIS
        True when this shell was spawned by Wave, so wsh can reach the app.
    #>
    [CmdletBinding()]
    param()

    return [bool](($env:WAVETERM_JWT -or $env:WAVETERM_SWAPTOKEN) -and $env:WAVETERM_TABID)
}

function Invoke-WtwWshCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $ArgumentList
    )

    $exe = Get-WtwWshExe
    if (-not $exe) {
        return [PSCustomObject]@{ ExitCode = 127; Output = 'wsh not found' }
    }

    Write-Verbose "wsh command: $exe $($ArgumentList -join ' ')"
    $output = & $exe @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) { $exitCode = 0 }
    $text = (@($output) | ForEach-Object { "$_" }) -join [Environment]::NewLine
    # wsh prints "Error: ..." and still exits 0 for some RPC failures.
    if ($exitCode -eq 0 -and $text -match '^\s*Error:') { $exitCode = 1 }
    return [PSCustomObject]@{ ExitCode = $exitCode; Output = $text.Trim() }
}

function Get-WtwWaveTabBlocks {
    [CmdletBinding()]
    param([string] $TabId = $env:WAVETERM_TABID)

    if (-not $TabId) { return @() }
    $result = Invoke-WtwWshCommand -ArgumentList @('blocks', 'list', '--view=term', "--tab=$TabId", '--json')
    if ($result.ExitCode -ne 0 -or -not $result.Output) { return @() }

    try {
        return @($result.Output | ConvertFrom-Json -Depth 20 -ErrorAction Stop)
    } catch {
        return @()
    }
}

function Find-WtwWaveBlock {
    <#
    .SYNOPSIS
        Find a terminal block in the current Wave tab rooted at the target
        directory (cmd:cwd), falling back to a block titled with the pretty name.
    #>
    [CmdletBinding()]
    param(
        [string] $PrettyName,
        [string] $ProjectPath
    )

    $blocks = @(Get-WtwWaveTabBlocks)
    if ($ProjectPath) {
        $fullPath = [System.IO.Path]::GetFullPath($ProjectPath).TrimEnd('/', '\')
        $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
        foreach ($block in $blocks) {
            $cwd = Get-WtwPropertyValue -Object $block.meta -Name 'cmd:cwd'
            if (-not $cwd) { continue }
            $blockPath = [System.IO.Path]::GetFullPath("$cwd").TrimEnd('/', '\')
            if ([string]::Equals($blockPath, $fullPath, $comparison)) { return $block }
        }
    }

    if (-not $PrettyName) { return $null }
    foreach ($block in $blocks) {
        $title = Get-WtwPropertyValue -Object $block.meta -Name 'frame:title'
        if ([string]::Equals("$title", $PrettyName, [StringComparison]::Ordinal)) { return $block }
    }

    return $null
}

function Set-WtwWaveBlockFrame {
    <#
    .SYNOPSIS
        Title the block with the wtw pretty name and tint its frame with the
        worktree's Peacock color.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $BlockId,
        [string] $PrettyName,
        [string] $Color
    )

    $meta = @()
    if ($PrettyName) { $meta += "frame:title=$PrettyName" }
    if ($Color) { $meta += @("frame:bordercolor=$Color", "frame:activebordercolor=$Color") }
    if ($meta.Count -eq 0) { return }

    Invoke-WtwWshCommand -ArgumentList (@('setmeta', '-b', $BlockId) + $meta) | Out-Null
}

function Open-WtwWaveProject {
    <#
    .SYNOPSIS
        Open a wtw target as a Wave terminal block: focus the block already
        rooted at the target, otherwise create one with `wsh term <dir>`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectPath,
        [Parameter(Mandatory)][string] $PrettyName,
        [string] $Color
    )

    if (-not (Get-WtwWshExe)) {
        return [PSCustomObject]@{ Success = $false; Created = $false; Reason = 'wsh not found' }
    }
    if (-not (Test-WtwWaveSession)) {
        return [PSCustomObject]@{
            Success = $false; Created = $false
            Reason  = 'not running inside a Wave terminal (WAVETERM_JWT / WAVETERM_TABID not set). Run wtw from a Wave terminal block.'
        }
    }

    $fullPath = [System.IO.Path]::GetFullPath($ProjectPath)

    $existing = Find-WtwWaveBlock -PrettyName $PrettyName -ProjectPath $fullPath
    if ($existing -and $existing.blockid) {
        $blockId = "$($existing.blockid)"
        Set-WtwWaveBlockFrame -BlockId $blockId -PrettyName $PrettyName -Color $Color
        Invoke-WtwWshCommand -ArgumentList @('focusblock', '-b', $blockId) | Out-Null
        return [PSCustomObject]@{
            Success = $true; Created = $false; Path = $fullPath; Id = $blockId; Reason = $null
        }
    }

    $result = Invoke-WtwWshCommand -ArgumentList @('term', $fullPath)
    if ($result.ExitCode -ne 0) {
        return [PSCustomObject]@{ Success = $false; Created = $false; Path = $fullPath; Reason = $result.Output }
    }

    $blockId = $null
    if ($result.Output -match 'block:([0-9a-fA-F-]{36})') { $blockId = "block:$($Matches[1])" }
    if ($blockId) {
        Set-WtwWaveBlockFrame -BlockId $blockId -PrettyName $PrettyName -Color $Color
    }

    return [PSCustomObject]@{
        Success = $true; Created = $true; Path = $fullPath; Id = $blockId; Reason = $null
    }
}
