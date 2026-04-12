<#
.SYNOPSIS
    Writes the wtw registry to disk as JSON.

.DESCRIPTION
    Serializes the registry object to ~/.wtw/registry.json (see $script:WtwRegistryPath).
    Creates the parent directory if needed. Side effect: overwrites the registry file.

.PARAMETER Registry
    Registry object to persist (repos and worktrees).

.EXAMPLE
    Save-WtwRegistry -Registry $registry

.NOTES
    Depends on: $script:WtwRegistryPath from Get-WtwRegistry.ps1 dot-sourcing order.
#>
function Save-WtwRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [PSObject] $Registry
    )

    try {
        $dir = Split-Path $script:WtwRegistryPath -Parent
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
        $Registry | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwRegistryPath -Encoding utf8
    } catch {
        Write-Error "Failed to save registry to '$($script:WtwRegistryPath)': $_"
    }
}
