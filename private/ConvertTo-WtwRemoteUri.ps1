function ConvertTo-WtwRemotePath {
    <#
    .SYNOPSIS
        Normalise a remote filesystem path to its URI path form.
    .DESCRIPTION
        Windows paths need real work: `C:\Users\sno\repo` becomes
        `/c:/Users/sno/repo` — backslashes flipped, drive letter lower-cased, and
        a leading slash added. Getting any of those three wrong produces a URI
        VS Code accepts and then silently opens as an empty window, which is why
        this is its own function with its own tests rather than an inline replace.

        POSIX paths pass through unchanged apart from backslash normalisation.
    .PARAMETER Path
        Absolute path as it exists on the remote machine.
    .PARAMETER Platform
        'windows' | 'linux' | 'macos'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $Platform = 'linux'
    )

    $normalized = $Path -replace '\\', '/'

    if ($Platform -ieq 'windows') {
        # UNC (\\server\share) survives as //server/share — already URI-shaped.
        if ($normalized -match '^//') { return $normalized }
        if ($normalized -match '^([A-Za-z]):(/.*)?$') {
            $drive = $Matches[1].ToLowerInvariant()
            $rest = if ($Matches.Count -gt 2 -and $Matches[2]) { $Matches[2] } else { '/' }
            return "/${drive}:$rest"
        }
    }

    if (-not $normalized.StartsWith('/')) { $normalized = "/$normalized" }
    return $normalized
}

function ConvertTo-WtwRemoteUri {
    <#
    .SYNOPSIS
        Build a `vscode-remote://ssh-remote+<host>/<path>` URI.
    .DESCRIPTION
        Percent-escapes each path segment so worktrees with spaces in their name
        survive. The Windows drive segment (`c:`) is left alone — escaping its
        colon to %3A yields a URI VS Code cannot map back to a drive.
    .PARAMETER Path
        Absolute path on the remote machine.
    .PARAMETER HostName
        SSH host name as the ssh client resolves it (the authority suffix).
    .PARAMETER Platform
        'windows' | 'linux' | 'macos'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $HostName,
        [string] $Platform = 'linux'
    )

    $uriPath = ConvertTo-WtwRemotePath -Path $Path -Platform $Platform

    $escaped = @($uriPath -split '/' | ForEach-Object {
            if ([string]::IsNullOrEmpty($_)) { $_ }
            elseif ($_ -match '^[A-Za-z]:$') { $_ }
            else { [System.Uri]::EscapeDataString($_) }
        }) -join '/'

    return "vscode-remote://ssh-remote+$HostName$escaped"
}
