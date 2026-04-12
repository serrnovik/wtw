<#
.SYNOPSIS
    Tests whether a name matches any alias for a repo registry entry.

.DESCRIPTION
    Uses Get-WtwRepoAliases to expand aliases and checks membership.

.PARAMETER Repo
    Registry repo object (PSObject).

.PARAMETER Name
    Name or alias string to test.

.EXAMPLE
    Test-WtwAliasMatch -Repo $repo -Name 'my-alias'

.NOTES
    Depends on: Get-WtwRepoAliases
#>
function Test-WtwAliasMatch {
    param([PSObject] $Repo, [string] $Name)
    $aliases = Get-WtwRepoAliases $Repo
    return ($Name -in $aliases)
}
