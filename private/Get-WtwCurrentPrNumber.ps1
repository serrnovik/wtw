function Get-WtwCurrentPrNumber {
    <#
    .SYNOPSIS
        Returns the PR number for the current branch, or $null. Never throws.
    .DESCRIPTION
        Requires git (must be inside a work tree) and gh CLI with auth.
        Any missing prerequisite or error silently returns $null.
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    git rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return $null }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return $null }
    try {
        $num = gh pr view --json number --jq .number 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($num)) { return $null }
        return $num.Trim()
    } catch {
        return $null
    }
}
