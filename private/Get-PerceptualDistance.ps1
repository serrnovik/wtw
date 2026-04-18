function Get-PerceptualDistance {
    <#
    .SYNOPSIS
        Weighted Euclidean distance in RGB — approximates human perception.
        Based on the "redmean" formula from compuphase.
    #>
    param([int[]] $A, [int[]] $B)
    $rmean = ($A[0] + $B[0]) / 2.0
    $dr = $A[0] - $B[0]
    $dg = $A[1] - $B[1]
    $db = $A[2] - $B[2]
    return [math]::Sqrt(
        (2 + $rmean / 256.0) * $dr * $dr +
        4 * $dg * $dg +
        (2 + (255 - $rmean) / 256.0) * $db * $db
    )
}
