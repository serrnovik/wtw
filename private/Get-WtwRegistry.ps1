$script:WtwRegistryPath = Join-Path $HOME '.wtw' 'registry.json'

function Get-WtwRegistry {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:WtwRegistryPath)) {
        return [PSCustomObject]@{ repos = [PSCustomObject]@{} }
    }
    return Get-Content -Path $script:WtwRegistryPath -Raw | ConvertFrom-Json
}

function Save-WtwRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [PSObject] $Registry
    )

    $dir = Split-Path $script:WtwRegistryPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    $Registry | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwRegistryPath -Encoding utf8
}

function Get-WtwRepoAliases {
    # Returns array of aliases, handles both old "alias" (string) and new "aliases" (array)
    param([PSObject] $Repo)
    $result = @()
    if ($Repo.aliases) {
        $result = @($Repo.aliases)
    } elseif ($Repo.alias) {
        $result = @($Repo.alias)
    }
    return $result
}

function Test-WtwAliasMatch {
    param([PSObject] $Repo, [string] $Name)
    $aliases = Get-WtwRepoAliases $Repo
    return ($Name -in $aliases)
}

function Get-WtwRepoFromCwd {
    [CmdletBinding()]
    param()

    $root = Resolve-WtwRepoRoot
    if (-not $root) { return $null, $null }

    $registry = Get-WtwRegistry
    $repoNames = $registry.repos.PSObject.Properties.Name
    foreach ($name in $repoNames) {
        $repo = $registry.repos.$name
        $mainResolved = [System.IO.Path]::GetFullPath($repo.mainPath)
        if ($mainResolved -eq [System.IO.Path]::GetFullPath($root)) {
            return $name, $repo
        }
        # Check if we're inside a worktree of this repo
        if ($repo.worktrees) {
            foreach ($taskName in $repo.worktrees.PSObject.Properties.Name) {
                $wt = $repo.worktrees.$taskName
                $wtResolved = [System.IO.Path]::GetFullPath($wt.path)
                if ($wtResolved -eq [System.IO.Path]::GetFullPath($root)) {
                    return $name, $repo
                }
            }
        }
    }
    return $null, $null
}

function Resolve-WtwRepo {
    [CmdletBinding()]
    param(
        [string] $RepoAlias
    )

    $registry = Get-WtwRegistry
    if ($RepoAlias) {
        foreach ($name in $registry.repos.PSObject.Properties.Name) {
            $repo = $registry.repos.$name
            if ((Test-WtwAliasMatch $repo $RepoAlias) -or $name -eq $RepoAlias) {
                return $name, $repo
            }
        }
        Write-Error "Repo '$RepoAlias' not found in registry. Run 'wtw init' first."
        return $null, $null
    }
    $name, $repo = Get-WtwRepoFromCwd
    if (-not $name) {
        Write-Error "Not inside a registered repo. Run 'wtw init' or use --repo."
        return $null, $null
    }
    return $name, $repo
}
