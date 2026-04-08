function Test-WtwAliasMatch {
    param([PSObject] $Repo, [string] $Name)
    $aliases = Get-WtwRepoAliases $Repo
    return ($Name -in $aliases)
}
