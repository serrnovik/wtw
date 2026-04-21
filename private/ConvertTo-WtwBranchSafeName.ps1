function ConvertTo-WtwBranchSafeName {
    <#
    .SYNOPSIS
        Normalize a human task label into a git-branch and filesystem-safe slug.
    .DESCRIPTION
        Trims input, maps whitespace to underscores, removes characters that are
        invalid or awkward in branch names and Windows path segments, collapses
        repeated underscores, and strips leading punctuation that git rejects
        for ref names.
    .PARAMETER Name
        Raw task name (e.g. from `wtw create "my feature name"`).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $s = $Name.Trim()
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }

    # Whitespace runs → single underscore
    $s = [regex]::Replace($s, '\s+', '_')

    # Path / ref / Windows-hostile characters
    $s = [regex]::Replace($s, '[\\/:*?"<>|~\^\[\]\p{C}]', '_')

    # Git: consecutive dots are invalid in ref names
    $s = [regex]::Replace($s, '\.{2,}', '_')

    $s = [regex]::Replace($s, '_+', '_')
    $s = $s.Trim('_', '.')

    # Git: ref cannot start with '-' or '.'
    $s = [regex]::Replace($s, '^[-.]+', '')

    if ($s -match '\.lock$') {
        $s = $s.Substring(0, $s.Length - 5) + '_lock'
    }

    if ([string]::IsNullOrWhiteSpace($s)) { return '' }

    return $s
}
