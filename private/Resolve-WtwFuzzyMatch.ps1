function Resolve-WtwFuzzyMatch {
    <#
    .SYNOPSIS
        Finds the closest match for a name from a list of candidates using Levenshtein distance.
    .OUTPUTS
        PSCustomObject with: Match (string or $null), Suggestions (string[] if tied)
    #>
    [CmdletBinding()]
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
    # Re-wrap: Sort-Object on an empty array emits nothing, leaving $null behind,
    # and `.Count` on $null throws under the module's Set-StrictMode -Version
    # Latest. The caller still saw "no match" because the errors went to the
    # error stream and the function returned nothing — which is why an assertion
    # of "returns null for an unknown editor" never caught it.
    $fuzzyMatches = @($fuzzyMatches | Sort-Object Dist)

    if ($fuzzyMatches.Count -eq 0) {
        return [PSCustomObject]@{ Match = $null; Suggestions = @() }
    }

    $best = $fuzzyMatches[0]
    $tied = @($fuzzyMatches | Where-Object { $_.Dist -eq $best.Dist })

    if ($tied.Count -eq 1) {
        Write-Verbose "Fuzzy match: '$Name' -> '$($best.Target)'"
        return [PSCustomObject]@{ Match = $best.Target; Suggestions = @() }
    }

    return [PSCustomObject]@{ Match = $null; Suggestions = @($tied | ForEach-Object { $_.Target }) }
}
