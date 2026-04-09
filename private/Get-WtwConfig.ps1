$script:WtwConfigDir = Join-Path $HOME '.wtw'
$script:WtwConfigPath = Join-Path $script:WtwConfigDir 'config.json'

function Get-WtwConfig {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:WtwConfigPath)) {
        return $null
    }
    return Get-Content -Path $script:WtwConfigPath -Raw | ConvertFrom-Json
}
