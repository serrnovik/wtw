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
    $found = Get-Command $Cmd -ErrorAction SilentlyContinue
    if (-not $found) { return $false }
    $resolved = $found.Source
    if (-not $resolved) { return $true }   # builtin / function — trust it
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
