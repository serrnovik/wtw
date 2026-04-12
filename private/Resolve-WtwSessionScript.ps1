# Resolve the session script for a given shell type.
# Checks per-shell overrides (sessionScripts.zsh, sessionScripts.bash) first,
# then falls back to the default sessionScript.
function Resolve-WtwSessionScript {
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
