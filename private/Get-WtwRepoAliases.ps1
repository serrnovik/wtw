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
