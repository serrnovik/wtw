$script:WtwConfigDir = Join-Path $HOME '.wtw'
$script:WtwConfigPath = Join-Path $script:WtwConfigDir 'config.json'

<#
.SYNOPSIS
    Reads the wtw global configuration from JSON.

.DESCRIPTION
    Loads ~/.wtw/config.json if present; returns $null if missing.

.EXAMPLE
    Get-WtwConfig

.NOTES
    Side effect: defines $script:WtwConfigDir and $script:WtwConfigPath when this file is loaded.
#>
function Get-WtwConfig {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:WtwConfigPath)) {
        return $null
    }
    return Get-Content -Path $script:WtwConfigPath -Raw | ConvertFrom-Json
}
