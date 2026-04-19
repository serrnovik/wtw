function Resolve-WtwColorArgs {
    <#
    .SYNOPSIS
        Resolve positional arguments for the 'color' command.
    #>
    param([array]$Positional)
    $splat = @{}
    if ($Positional.Count -eq 1) {
        if ($Positional[0] -match '^#?[0-9a-fA-F]{6}$' -or $Positional[0] -eq 'random') {
            $splat['Color'] = $Positional[0]
        } else {
            $splat['Name'] = $Positional[0]
        }
    } elseif ($Positional.Count -gt 1) {
        $splat['Name'] = $Positional[0]
        $splat['Color'] = $Positional[1]
    }
    return $splat
}
