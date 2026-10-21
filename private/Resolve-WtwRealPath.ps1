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
    if ($script:WtwRealPathCache.ContainsKey($Path)) { return $script:WtwRealPathCache[$Path] }

    if ($IsMacOS -or $IsLinux) {
        # `realpath` is BSD on macOS and GNU on Linux — both follow symlinks
        # and emit a single absolute path on stdout.
        $real = & realpath -- $Path 2>$null
        if ($LASTEXITCODE -eq 0 -and $real) {
            $real = $real.TrimEnd("`r", "`n")
            $script:WtwRealPathCache[$Path] = $real
            return $real
        }
    }

    # Windows / no realpath available: Convert-Path resolves PSDrive
    # qualifiers and normalizes separators but does not follow NTFS junction
    # points reliably either. Good enough as a fallback for the registry
    # match.
    try {
        $converted = Convert-Path -LiteralPath $Path -ErrorAction Stop
        $script:WtwRealPathCache[$Path] = $converted
        return $converted
    } catch { return $Path }
}

# Paths that resolved, keyed by the input string. Invoke-Wtw clears it per
# command. A missing path is not cached: it may be created later in the call
# (``wtw create``) and then resolve differently, e.g. /var → /private/var.
$script:WtwRealPathCache = @{}

function Initialize-WtwRealPathCache {
    <#
    .SYNOPSIS
        Resolve many paths with one ``realpath`` process instead of one each.
    .DESCRIPTION
        ``wtw list --all`` compares every git worktree of every repo. Starting
        ``realpath`` once per comparison took seconds on macOS. Only existing
        paths are passed, so each prints one line. If the line count does not
        match, nothing is cached and Resolve-WtwRealPath falls back per path.
    #>
    [CmdletBinding()]
    param([AllowNull()] [string[]] $Paths)

    if (-not ($IsMacOS -or $IsLinux)) { return }
    $todo = @($Paths | Where-Object {
            $_ -and -not $script:WtwRealPathCache.ContainsKey($_) -and -not $_.Contains("`n") -and
            (Test-Path -LiteralPath $_)
        } | Select-Object -Unique)
    if ($todo.Count -eq 0) { return }

    $real = @(& realpath -- @todo 2>$null)
    if ($LASTEXITCODE -ne 0 -or $real.Count -ne $todo.Count) { return }
    for ($i = 0; $i -lt $todo.Count; $i++) {
        $script:WtwRealPathCache[$todo[$i]] = $real[$i].TrimEnd("`r", "`n")
    }
}
