function Test-WtwShellRcHasWrapper {
    <#
    .SYNOPSIS
        True when a shell rc already sources the given wtw wrapper.
    .DESCRIPTION
        `wtw install` used to look only for the comment
        "wtw — worktree + workspace manager". Chezmoi and hand-written
        profiles often source ~/.wtw/shell/wtw.zsh without that comment,
        so install appended a second source and every hook error printed twice.
    #>
    [CmdletBinding()]
    param(
        [string] $RcContent,
        [Parameter(Mandatory)]
        [string] $WrapperFileName
    )

    if ([string]::IsNullOrWhiteSpace($RcContent)) { return $false }
    if ($RcContent -match 'wtw.*worktree.*workspace.*manager') { return $true }
    return $RcContent.Contains($WrapperFileName, [System.StringComparison]::Ordinal)
}
