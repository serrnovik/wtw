function Get-WtwEditDistance {
    <#
    .SYNOPSIS
        Computes Levenshtein edit distance between two strings (case-insensitive).
    #>
    param([string] $A, [string] $B)
    $a = $A.ToLowerInvariant()
    $b = $B.ToLowerInvariant()
    $la = $a.Length; $lb = $b.Length
    if ($la -eq 0) { return $lb }
    if ($lb -eq 0) { return $la }

    $d = [int[, ]]::new($la + 1, $lb + 1)
    for ($i = 0; $i -le $la; $i++) { $d[$i, 0] = $i }
    for ($j = 0; $j -le $lb; $j++) { $d[0, $j] = $j }
    for ($i = 1; $i -le $la; $i++) {
        for ($j = 1; $j -le $lb; $j++) {
            $cost = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
            $d[$i, $j] = [Math]::Min(
                [Math]::Min($d[($i - 1), $j] + 1, $d[$i, ($j - 1)] + 1),
                $d[($i - 1), ($j - 1)] + $cost
            )
        }
    }
    return $d[$la, $lb]
}
