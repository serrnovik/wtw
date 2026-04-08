function Resolve-WtwFuzzyMatch {
    <#
    .SYNOPSIS
        Finds the closest match for a name from a list of candidates using Levenshtein distance.
    .OUTPUTS
        PSCustomObject with: Match (string or $null), Suggestions (string[] if tied)
    #>
    param(
        [Parameter(Mandatory)][string]   $Name,
        [Parameter(Mandatory)][string[]] $Candidates
    )

    $maxDist = [Math]::Max(2, [Math]::Floor($Name.Length / 3))
    $fuzzyMatches = @()
    foreach ($candidate in $Candidates) {
        $dist = Get-WtwEditDistance $Name $candidate
        if ($dist -le $maxDist) {
            $fuzzyMatches += [PSCustomObject]@{ Target = $candidate; Dist = $dist }
        }
    }
    $fuzzyMatches = $fuzzyMatches | Sort-Object Dist

    if ($fuzzyMatches.Count -eq 0) {
        return [PSCustomObject]@{ Match = $null; Suggestions = @() }
    }

    $best = $fuzzyMatches[0]
    $tied = @($fuzzyMatches | Where-Object { $_.Dist -eq $best.Dist })

    if ($tied.Count -eq 1) {
        Write-Host "  Fuzzy match: '$Name' → '$($best.Target)'" -ForegroundColor Yellow
        return [PSCustomObject]@{ Match = $best.Target; Suggestions = @() }
    }

    return [PSCustomObject]@{ Match = $null; Suggestions = @($tied | ForEach-Object { $_.Target }) }
}
