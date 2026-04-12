# Persist the wtw config object to ~/.wtw/config.json.
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
