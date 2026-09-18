function Get-WtwGalleryLatestVersionText {
    <#
    .SYNOPSIS
        Read the latest published wtw version from the PowerShell Gallery.
    .DESCRIPTION
        ``FindPackagesById()?id='wtw'&$filter=IsLatestVersion`` lags behind
        newly published versions — it kept returning 0.2.26 after 0.2.28 was
        already ``IsLatestVersion`` on ``Packages()``. Prefer ``Packages()``
        filtered to the latest package; if that fails, take the max version
        from the unfiltered ``FindPackagesById`` list.
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1, 30)]
        [int] $TimeoutSec = 5
    )

    $versionPattern = '<d:Version>(?<version>[^<]+)</d:Version>'
    $regexOptions = [Text.RegularExpressions.RegexOptions]::CultureInvariant

    $latestUri = "https://www.powershellgallery.com/api/v2/Packages()?`$filter=Id eq 'wtw' and IsLatestVersion eq true"
    $response = Invoke-WebRequest -Uri $latestUri -TimeoutSec $TimeoutSec -ErrorAction Stop
    $match = [regex]::Match([string]$response.Content, $versionPattern, $regexOptions)
    if ($match.Success) {
        $text = $match.Groups['version'].Value
        [version]$text | Out-Null
        return $text
    }

    $allUri = "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='wtw'"
    $all = Invoke-WebRequest -Uri $allUri -TimeoutSec $TimeoutSec -ErrorAction Stop
    $parsed = foreach ($hit in [regex]::Matches([string]$all.Content, $versionPattern, $regexOptions)) {
        $parsedVersion = $null
        if ([version]::TryParse($hit.Groups['version'].Value, [ref] $parsedVersion)) {
            $parsedVersion
        }
    }
    $best = @($parsed) | Sort-Object -Descending | Select-Object -First 1
    if ($null -eq $best) {
        throw 'The PowerShell Gallery response did not contain a wtw version.'
    }
    return $best.ToString()
}

function Get-WtwUpdateStatus {
    <#
    .SYNOPSIS
        Report whether a newer wtw is published on the PowerShell Gallery.
    .DESCRIPTION
        Caches the Gallery answer in ~/.wtw/update-check.json so repeated calls
        cost nothing. An offline or unreachable Gallery is a normal outcome: the
        failed attempt is cached too, so a disconnected workstation does not
        retry on every command.

        This is the function the detached background refresh runs; the
        foreground notice never calls it, because it must not wait on a network
        request. See Write-WtwUpdateNotice.
    .EXAMPLE
        Get-WtwUpdateStatus -Force
        Refreshes the cache and returns the current/latest comparison.
    #>
    [CmdletBinding()]
    param(
        [TimeSpan] $CacheTtl = [TimeSpan]::FromHours(24),

        [ValidateRange(1, 30)]
        [int] $TimeoutSec = 5,

        [string] $CachePath = (Join-Path $HOME '.wtw/update-check.json'),

        [switch] $Force
    )

    $manifestPath = Join-Path $script:WtwModuleRoot 'wtw.psd1'
    $currentVersion = $null
    try {
        $currentVersion = [version](Import-PowerShellDataFile -LiteralPath $manifestPath).ModuleVersion
    } catch {
        $currentVersion = $null
    }

    $cacheFile = [IO.Path]::GetFullPath($CachePath)
    $cache = Read-WtwJsonFile -Path $cacheFile

    $now = [DateTime]::UtcNow
    $checkedAt = ConvertTo-WtwUtcDate -Value (Get-WtwPropertyValue -Object $cache -Name 'CheckedAtUtc')
    $cacheIsFresh = -not $Force -and $null -ne $checkedAt -and ($now - $checkedAt) -lt $CacheTtl

    $latestText = [string](Get-WtwPropertyValue -Object $cache -Name 'LatestVersion' -DefaultValue '')
    $status = [string](Get-WtwPropertyValue -Object $cache -Name 'Status' -DefaultValue 'Unknown')
    $source = 'cache'

    if (-not $cacheIsFresh) {
        $source = 'gallery'
        $status = 'Unavailable'
        try {
            $latestText = Get-WtwGalleryLatestVersionText -TimeoutSec $TimeoutSec
            $status = 'Available'
        } catch {
            # Offline is normal. The failed attempt is cached below so wtw does
            # not retry - or pause - on every command.
        }

        try {
            $cacheDirectory = Split-Path -Parent $cacheFile
            New-Item -ItemType Directory -Path $cacheDirectory -Force -ErrorAction Stop | Out-Null
            [ordered]@{
                CheckedAtUtc  = $now.ToString('O')
                LatestVersion = $latestText
                Status        = $status
            } | ConvertTo-Json | Set-Content -LiteralPath $cacheFile -Encoding utf8 -ErrorAction Stop
        } catch {
            # Update checks must never prevent wtw from running.
        }
        $checkedAt = $now
    }

    $latestVersion = $null
    if (-not [version]::TryParse($latestText, [ref] $latestVersion)) {
        $latestVersion = $null
    }

    [pscustomobject]@{
        CurrentVersion  = $currentVersion
        LatestVersion   = $latestVersion
        UpdateAvailable = $null -ne $latestVersion -and $null -ne $currentVersion -and $latestVersion -gt $currentVersion
        Status          = $status
        CheckedAtUtc    = $checkedAt
        Source          = $source
    }
}
