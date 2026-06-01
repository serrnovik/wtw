function Resolve-WtwRealPath {
    <#
    .SYNOPSIS
        Canonical filesystem path with symlinks resolved.
    .DESCRIPTION
        PowerShell's `Resolve-Path`, `Convert-Path`, and `[IO.Path]::GetFullPath`
        on macOS/Linux do not actually follow symlinks. We need that so the
        registry can match a path like `/var/folders/.../foo` against git's
        output `/private/var/folders/.../foo` (the same dir reached through
        macOS's firmlink). Shell out to BSD/GNU `realpath`, fall back to the
        Convert-Path approximation, then to the literal input.
    .PARAMETER Path
        Filesystem path to canonicalize.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)] [string] $Path)

    if (-not $Path) { return $Path }

    if ($IsMacOS -or $IsLinux) {
        # `realpath` is BSD on macOS and GNU on Linux — both follow symlinks
        # and emit a single absolute path on stdout.
        $real = & realpath -- $Path 2>$null
        if ($LASTEXITCODE -eq 0 -and $real) { return $real.Trim() }
    }

    # Windows / no realpath available: Convert-Path resolves PSDrive
    # qualifiers and normalizes separators but does not follow NTFS junction
    # points reliably either. Good enough as a fallback for the registry
    # match.
    try { return (Convert-Path -LiteralPath $Path -ErrorAction Stop) } catch { return $Path }
}
