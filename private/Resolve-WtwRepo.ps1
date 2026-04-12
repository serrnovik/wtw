<#
.SYNOPSIS
    Resolves a repo alias to a registry name and entry, or uses the current repo from cwd.

.DESCRIPTION
    Loads the registry via Get-WtwRegistry. If RepoAlias is set, finds a matching repo;
    otherwise uses Get-WtwRepoFromCwd. Emits errors when not found.

.PARAMETER RepoAlias
    Optional alias or canonical registry name.

.EXAMPLE
    Resolve-WtwRepo -RepoAlias 'myrepo'

.NOTES
    Depends on: Get-WtwRegistry, Test-WtwAliasMatch, Get-WtwRepoFromCwd
#>
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
