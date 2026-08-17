function Resolve-WtwEditorPreference {
    <#
    .SYNOPSIS
        Pick an editor from a config value that may be a single name or a chain.
    .DESCRIPTION
        `"editor"` in ~/.wtw/config.json accepts either form:

            "editor": "cursor"
            "editor": ["cursor", "code"]

        The array is an ordered preference — first *runnable* wins, not "open in
        all of them". That makes one config file portable across machines with
        different editors installed, which is the normal case once worktrees are
        opened from more than one box.

        Only VS Code family members can be probed for runnability (they are the
        ones with a CLI on PATH). A non-family entry such as `t3` or `cmux` is
        returned as-is the moment it is reached, because "is it installed" for
        those is an app-bundle question their own launchers already answer.

        Falls back to the last entry when nothing in the chain is runnable, so
        the caller still produces the editor's own "not installed" diagnostic
        rather than a vague wtw error.
    .PARAMETER Editor
        Raw config value: string, array of strings, or an already-resolved
        editor descriptor hashtable (passed straight through).
    .PARAMETER Require
        Only accept candidates satisfying this predicate, e.g. "has a working
        Remote-SSH extension". Receives the resolved editor name.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] [object] $Editor,
        [scriptblock] $Require
    )

    if ($null -eq $Editor) { return $null }

    # Already a descriptor (@{ type = 'cmux'; ... }) — nothing to choose between.
    if ($Editor -is [System.Collections.IDictionary]) { return $Editor }

    # Re-wrap: a Where-Object that keeps one item yields a bare string, and
    # `.Count` on a string throws under the module's Set-StrictMode -Version Latest.
    $candidates = @(@($Editor) | Where-Object { $_ -is [string] -and $_ })
    if ($candidates.Count -eq 0) { return $Editor }

    foreach ($candidate in $candidates) {
        $resolved = Resolve-WtwEditorCommand $candidate
        if (-not $resolved) { continue }

        # Non-family (hashtable descriptor): its launcher owns the install check.
        if ($resolved -is [System.Collections.IDictionary]) {
            if ($Require -and -not (& $Require $candidate)) { continue }
            return $resolved
        }

        if (-not (Get-WtwEditorCliName -Cmd $resolved)) { continue }
        if ($Require -and -not (& $Require $resolved)) { continue }
        return $resolved
    }

    # Nothing runnable — hand back the last named entry so the launcher can emit
    # its own actionable "install it / put it on PATH" message.
    return (Resolve-WtwEditorCommand $candidates[-1])
}
