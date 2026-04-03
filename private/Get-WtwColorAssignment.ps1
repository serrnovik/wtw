$script:WtwColorsPath = Join-Path $HOME '.wtw' 'colors.json'

$script:WtwDefaultPalette = @(
    '#e05d44', '#2ba7d0', '#97ca00', '#b300b3', '#fe7d37',
    '#007ec6', '#44cc11', '#dfb317', '#a4a61d', '#e26d8a',
    '#8b5cf6', '#0e8a16', '#d93f0b', '#1d76db', '#5319e7',
    '#0075ca', '#d876e3', '#f9a825', '#00c853', '#795548'
)

function Get-WtwColors {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:WtwColorsPath)) {
        return [PSCustomObject]@{
            palette     = $script:WtwDefaultPalette
            assignments = [PSCustomObject]@{}
        }
    }
    return Get-Content -Path $script:WtwColorsPath -Raw | ConvertFrom-Json
}

function Save-WtwColors {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [PSObject] $Colors
    )

    $dir = Split-Path $script:WtwColorsPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    $Colors | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwColorsPath -Encoding utf8
}
