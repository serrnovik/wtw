function New-WtwColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $RepoName,

        [Parameter(Position = 1)]
        [string] $TaskName = 'main'
    )

    $colors = Get-WtwColors
    $key = "$RepoName/$TaskName"

    # Already assigned?
    if ($colors.assignments.PSObject.Properties.Name -contains $key) {
        return $colors.assignments.$key
    }

    # Collect all colors currently assigned to this repo
    $usedColors = @()
    foreach ($prop in $colors.assignments.PSObject.Properties) {
        if ($prop.Name -like "$RepoName/*") {
            $usedColors += $prop.Value.ToLower()
        }
    }

    # Pick first palette color not used by this repo
    $palette = @($colors.palette)
    $picked = $null
    foreach ($c in $palette) {
        if ($c.ToLower() -notin $usedColors) {
            $picked = $c
            break
        }
    }

    # If all used, recycle from start
    if (-not $picked) {
        $picked = $palette[($usedColors.Count) % $palette.Count]
    }

    # Save assignment
    $colors.assignments | Add-Member -NotePropertyName $key -NotePropertyValue $picked -Force
    Save-WtwColors $colors

    return $picked
}
