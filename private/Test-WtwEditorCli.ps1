function Test-WtwEditorCli {
    <#
    .SYNOPSIS
        Return $true if a CLI command resolves to a runnable binary.
    .DESCRIPTION
        We deliberately do NOT invoke `--version`: on a dangling symlink,
        pwsh's `& path` outside a pipeline silently succeeds with
        $LASTEXITCODE=0, and inside a pipeline it raises "Cannot run a
        document in the middle of a pipeline".

        Filesystem check instead: if Get-Command resolves to a symlink,
        follow the chain via FileInfo.ResolveLinkTarget($true) and verify
        the final target exists. Plain files just need Get-Item to return a
        FileInfo. Catches the `~/.antigravity/antigravity/bin/antigravity`
        stub the Antigravity v1 installer leaves behind when v2 ships its
        CLI as `antigravity-ide` at /Applications/Antigravity IDE.app/.
    #>
    param([string]$Cmd)
    # Functions and aliases are not editor CLIs. Trusting them lets a shell
    # `function cursor { wtw cursor; }` (or a Pester stub) recurse until
    # "Stack overflow." Only an Application / ExternalScript on PATH counts.
    $found = @(Get-Command $Cmd -CommandType Application, ExternalScript -All -ErrorAction SilentlyContinue)
    foreach ($candidate in $found) {
        if (Test-WtwEditorCliCandidate $candidate) { return $true }
    }
    return $false
}

function Test-WtwCursorAgentShim {
    <#
    .SYNOPSIS
        The ~/.local/bin/cursor stub from `cursor agent` re-execs another cursor.
    #>
    param([string] $Path)
    if (-not $Path) { return $false }
    $normalized = $Path.Replace('\', '/').TrimEnd('/')
    if ($normalized -eq "$($HOME.Replace('\', '/'))/.local/bin/cursor") { return $true }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $head = Get-Content -LiteralPath $Path -TotalCount 20 -ErrorAction Stop
        return [bool]($head -match 'excluding the current shim')
    } catch {
        return $false
    }
}

function Test-WtwEditorCliCandidate {
    param($found)
    if (-not $found) { return $false }
    $resolved = $found.Source
    if (-not $resolved) { return $false }
    if (Test-WtwCursorAgentShim $resolved) { return $false }
    $item = Get-Item -LiteralPath $resolved -ErrorAction SilentlyContinue
    if (-not $item) { return $false }
    # Non-symlink: a FileInfo means it exists as a regular file.
    if (-not $item.LinkType) { return ($item -is [System.IO.FileInfo]) }
    # Symlink: walk the full chain and verify the final target exists.
    # Dangling links return a FileSystemInfo with Exists=$false.
    try {
        $target = [System.IO.FileInfo]::new($resolved).ResolveLinkTarget($true)
        return ($null -ne $target -and $target.Exists)
    } catch {
        return $false
    }
}
