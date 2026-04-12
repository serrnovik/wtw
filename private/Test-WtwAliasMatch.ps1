# Check whether a given name matches any alias of a repo entry.
function Test-WtwAliasMatch {
    param([PSObject] $Repo, [string] $Name)
    $aliases = Get-WtwRepoAliases $Repo
    return ($Name -in $aliases)
}
