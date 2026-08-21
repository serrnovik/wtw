function Write-WtwInstallRecord {
    <#
    .SYNOPSIS
        Record how the copy of wtw in InstallRoot got there.
    .DESCRIPTION
        Writes INSTALLATION.json next to the installed module. Without it there
        is no way to tell a copy that `wtw install` made from a checkout apart
        from one `wtw update` pulled off the PowerShell Gallery, and the two need
        different update commands — see Get-WtwInstallInfo.

        Best effort: a read-only HOME degrades the record to "Manual" on the next
        read, which is the safe assumption, rather than failing the install.
    .PARAMETER Origin
        'Manual' for a copy taken from a source checkout, 'Gallery' for the
        published package.
    .EXAMPLE
        Write-WtwInstallRecord -InstallRoot ~/.wtw/module -Origin Manual -Version 0.2.10 -SourcePath /repo
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $InstallRoot,

        [Parameter(Mandatory)]
        [ValidateSet('Manual', 'Gallery')]
        [string] $Origin,

        [AllowNull()]
        [object] $Version,

        [string] $SourcePath,

        [string] $SourceCommit
    )

    try {
        if (-not $SourceCommit -and $SourcePath -and (Get-Command git -ErrorAction SilentlyContinue)) {
            $commit = & git -C $SourcePath rev-parse HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($commit)) {
                $SourceCommit = $commit.Trim()
            }
        }

        [ordered]@{
            Origin         = $Origin
            Version        = if ($null -ne $Version) { [string]$Version } else { '' }
            SourcePath     = [string]$SourcePath
            SourceCommit   = [string]$SourceCommit
            InstalledAtUtc = [DateTime]::UtcNow.ToString('O')
        } | ConvertTo-Json -Depth 3 |
            Set-Content -LiteralPath (Join-Path $InstallRoot 'INSTALLATION.json') -Encoding utf8 -ErrorAction Stop
    } catch {
        # Provenance is a convenience, never a reason to fail an install.
    }
}
