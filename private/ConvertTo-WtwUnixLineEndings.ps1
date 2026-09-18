function ConvertTo-WtwUnixLineEndings {
    <#
    .SYNOPSIS
        Rewrite a Unix shell file, or every .zsh/.bash/.sh under a directory, as LF.
    .DESCRIPTION
        zsh and bash treat CR as a command. A Windows checkout or a Gallery
        package packed from one can ship wtw.zsh as CRLF even when wtw.bash
        is LF — `*.bash` was pinned in gitattributes and `*.zsh` was not.
        Install, update, and publish run this so the installed hook is
        always sourceable, regardless of how the bytes arrived.
    .PARAMETER Path
        A file to rewrite, or a directory to walk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $unixExtensions = @('.zsh', '.bash', '.sh')
    $targets = @()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $targets = @(Get-Item -LiteralPath $Path)
    } elseif (Test-Path -LiteralPath $Path -PathType Container) {
        $targets = @(
            Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $unixExtensions -contains $_.Extension }
        )
    } else {
        return
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    foreach ($file in $targets) {
        if ($unixExtensions -notcontains $file.Extension) { continue }

        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $offset = 0
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        if ($hasBom) { $offset = 3 }

        $hasCr = $false
        for ($i = $offset; $i -lt $bytes.Length; $i++) {
            if ($bytes[$i] -eq 13) {
                $hasCr = $true
                break
            }
        }
        if (-not $hasCr) { continue }

        $text = [System.Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)
        $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
        [System.IO.File]::WriteAllText($file.FullName, $text, $utf8NoBom)
    }
}
