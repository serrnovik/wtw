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
