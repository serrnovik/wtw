function ConvertTo-WtwWorkspaceFileStem {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Name)

    # Keep color-circle emoji and readable spaces, while producing a name that
    # is valid on macOS, Windows, and Linux.
    $stem = $Name -replace '[<>:"/\\|?*\x00-\x1F]', '-'
    $stem = ($stem -replace '\s+', ' ').Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($stem)) { return 'workspace' }

    return $stem
}
