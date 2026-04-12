$script:WtwRegistryPath = Join-Path $HOME '.wtw' 'registry.json'

<#
.SYNOPSIS
    Reads the wtw registry of repos and worktrees from JSON.

.DESCRIPTION
    Loads ~/.wtw/registry.json ($script:WtwRegistryPath). Returns an empty repos object
    if the file does not exist.

.EXAMPLE
    Get-WtwRegistry

.NOTES
    Side effect: defines $script:WtwRegistryPath when this file is loaded.
#>
function Get-WtwRegistry {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:WtwRegistryPath)) {
        return [PSCustomObject]@{ repos = [PSCustomObject]@{} }
    }
    return Get-Content -Path $script:WtwRegistryPath -Raw | ConvertFrom-Json
}
