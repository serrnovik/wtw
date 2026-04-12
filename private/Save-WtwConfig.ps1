<#
.SYNOPSIS
    Writes the wtw global config object to disk as JSON.

.DESCRIPTION
    Ensures ~/.wtw exists, then writes config to ~/.wtw/config.json ($script:WtwConfigPath).
    Side effect: overwrites the config file.

.PARAMETER Config
    Configuration object to persist.

.EXAMPLE
    Save-WtwConfig -Config $config

.NOTES
    Depends on: $script:WtwConfigDir, $script:WtwConfigPath from Get-WtwConfig.ps1 load order.
#>
function Save-WtwConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [PSObject] $Config
    )

    if (-not (Test-Path $script:WtwConfigDir)) {
        New-Item -Path $script:WtwConfigDir -ItemType Directory -Force | Out-Null
    }
    $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwConfigPath -Encoding utf8
}
