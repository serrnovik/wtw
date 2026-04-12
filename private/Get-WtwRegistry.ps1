# Read the wtw registry of repos and worktrees (~/.wtw/registry.json).
$script:WtwRegistryPath = Join-Path $HOME '.wtw' 'registry.json'

function Get-WtwRegistry {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:WtwRegistryPath)) {
        return [PSCustomObject]@{ repos = [PSCustomObject]@{} }
    }
    return Get-Content -Path $script:WtwRegistryPath -Raw | ConvertFrom-Json
}
