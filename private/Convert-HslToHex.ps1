function Convert-HslToHex {
    param([double] $H, [double] $S, [double] $L)

    $c = (1 - [math]::Abs(2 * $L - 1)) * $S
    $x = $c * (1 - [math]::Abs(($H / 60) % 2 - 1))
    $m = $L - $c / 2

    $r1 = 0; $g1 = 0; $b1 = 0
    if ($H -lt 60) { $r1 = $c; $g1 = $x; $b1 = 0 }
    elseif ($H -lt 120) { $r1 = $x; $g1 = $c; $b1 = 0 }
    elseif ($H -lt 180) { $r1 = 0; $g1 = $c; $b1 = $x }
    elseif ($H -lt 240) { $r1 = 0; $g1 = $x; $b1 = $c }
    elseif ($H -lt 300) { $r1 = $x; $g1 = 0; $b1 = $c }
    else { $r1 = $c; $g1 = 0; $b1 = $x }

    $r = [int](($r1 + $m) * 255)
    $g = [int](($g1 + $m) * 255)
    $b = [int](($b1 + $m) * 255)

    return "#$(ConvertTo-HexComponent $r)$(ConvertTo-HexComponent $g)$(ConvertTo-HexComponent $b)"
}
