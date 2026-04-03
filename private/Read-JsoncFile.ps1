function Read-JsoncFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path.Replace('~', $HOME))
    if (-not (Test-Path $resolvedPath)) {
        return $null
    }

    $raw = Get-Content -Path $resolvedPath -Raw -ErrorAction Stop
    # Strip single-line comments
    $raw = $raw -replace '(?m)^\s*//.*$', ''
    # Strip trailing commas before } or ]
    $raw = $raw -replace ',\s*([\}\]])', '$1'
    return $raw | ConvertFrom-Json
}
