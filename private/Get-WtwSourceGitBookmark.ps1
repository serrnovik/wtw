function Get-WtwSourceGitBookmark {
    <#
    .SYNOPSIS
        Map a #rrggbb hex color to the nearest SourceGit Bookmark id (1–7).
    .DESCRIPTION
        SourceGit's bookmark palette is fixed in src/Models/Bookmarks.cs as
        Avalonia named brushes:
          0 = none, 1 = Red, 2 = Orange, 3 = Gold, 4 = ForestGreen,
          5 = DarkCyan, 6 = DeepSkyBlue, 7 = Purple
        Returns the index with the smallest Euclidean RGB distance to $Hex.
        Returns 0 when $Hex is empty or invalid.
    #>
    param([string] $Hex)

    if ([string]::IsNullOrWhiteSpace($Hex)) { return 0 }
    $clean = $Hex.TrimStart('#')
    if ($clean -notmatch '^[0-9a-fA-F]{6}$') { return 0 }

    $r = [Convert]::ToInt32($clean.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($clean.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($clean.Substring(4, 2), 16)

    $palette = @(
        @{ Id = 1; R = 0xFF; G = 0x00; B = 0x00 }   # Red
        @{ Id = 2; R = 0xFF; G = 0xA5; B = 0x00 }   # Orange
        @{ Id = 3; R = 0xFF; G = 0xD7; B = 0x00 }   # Gold
        @{ Id = 4; R = 0x22; G = 0x8B; B = 0x22 }   # ForestGreen
        @{ Id = 5; R = 0x00; G = 0x8B; B = 0x8B }   # DarkCyan
        @{ Id = 6; R = 0x00; G = 0xBF; B = 0xFF }   # DeepSkyBlue
        @{ Id = 7; R = 0x80; G = 0x00; B = 0x80 }   # Purple
    )

    $bestId = 1
    $bestDist = [double]::MaxValue
    foreach ($p in $palette) {
        $dr = $r - $p.R; $dg = $g - $p.G; $db = $b - $p.B
        $d = [double]($dr * $dr + $dg * $dg + $db * $db)
        if ($d -lt $bestDist) {
            $bestDist = $d
            $bestId = $p.Id
        }
    }
    return $bestId
}
