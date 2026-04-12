function Resolve-WtwSessionScript {
    <#
    .SYNOPSIS
        Resolve the session script for a given shell type.
    .DESCRIPTION
        Checks per-shell overrides (sessionScripts.zsh, sessionScripts.bash) first,
        then falls back to the default sessionScript property on the repo entry.
    .PARAMETER RepoEntry
        The registry repo object containing sessionScript and sessionScripts properties.
    .PARAMETER Shell
        Shell type to resolve for: 'zsh', 'bash', 'pwsh', or empty (defaults to pwsh).
    .EXAMPLE
        Resolve-WtwSessionScript -RepoEntry $repo -Shell 'zsh'
        Returns the zsh-specific session script, or the default if no override exists.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSObject] $RepoEntry,

        [string] $Shell  # 'zsh', 'bash', 'pwsh', or empty (= pwsh default)
    )

    # Check per-shell override
    if ($Shell -and $RepoEntry.sessionScripts) {
        $override = $RepoEntry.sessionScripts.$Shell
        if ($override) { return $override }
    }

    # Fall back to default
    return $RepoEntry.sessionScript ?? ''
}
