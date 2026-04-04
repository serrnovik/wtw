function Resolve-WtwRepoRoot {
    [CmdletBinding()]
    param(
        [string] $Path
    )

    $target = if ($Path) { $Path } else { (Get-Location).Path }
    $prev = $null
    while ($target -and $target -ne $prev) {
        if (Test-Path (Join-Path $target '.git')) {
            return $target
        }
        $prev = $target
        $target = Split-Path $target -Parent
    }
    # Fallback to git command
    try {
        $root = git -C (Get-Location).Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $root) { return $root }
    } catch {}
    return $null
}
