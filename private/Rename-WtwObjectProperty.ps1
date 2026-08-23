function Rename-WtwObjectProperty {
    <#
    .SYNOPSIS
        Rebuild a PSCustomObject with one property renamed, preserving order.
    .DESCRIPTION
        Registry maps (repos, worktrees, color assignments) are stored as
        note-properties, not hashtables. Renaming a key means copying every
        property onto a new object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [PSObject] $Object,

        [Parameter(Mandatory)]
        [string] $OldName,

        [Parameter(Mandatory)]
        [string] $NewName
    )

    $result = [PSCustomObject]@{}
    if (-not $Object) { return $result }

    foreach ($prop in $Object.PSObject.Properties) {
        $name = if ($prop.Name -eq $OldName) { $NewName } else { $prop.Name }
        $result | Add-Member -NotePropertyName $name -NotePropertyValue $prop.Value
    }
    return $result
}

function Rename-WtwColorAssignmentKey {
    <#
    .SYNOPSIS
        Move a colors.json assignment from one repo/task key to another.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $OldKey,
        [Parameter(Mandatory)] [string] $NewKey
    )

    if ($OldKey -eq $NewKey) { return }
    $colors = Get-WtwColors
    $names = Get-WtwPropertyNames -Object $colors.assignments
    if ($names -notcontains $OldKey) { return }

    $colors.assignments = Rename-WtwObjectProperty -Object $colors.assignments -OldName $OldKey -NewName $NewKey
    Save-WtwColors $colors
}

function Rename-WtwColorAssignmentRepoPrefix {
    <#
    .SYNOPSIS
        Rewrite every colors.json key `OldRepo/...` to `NewRepo/...`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $OldRepo,
        [Parameter(Mandatory)] [string] $NewRepo
    )

    if ($OldRepo -eq $NewRepo) { return }
    $colors = Get-WtwColors
    $prefix = "${OldRepo}/"
    $newAssignments = [PSCustomObject]@{}
    $changed = $false
    foreach ($prop in $colors.assignments.PSObject.Properties) {
        $name = $prop.Name
        if ($name -eq "${OldRepo}/main" -or $name.StartsWith($prefix)) {
            $name = $NewRepo + $name.Substring($OldRepo.Length)
            $changed = $true
        }
        $newAssignments | Add-Member -NotePropertyName $name -NotePropertyValue $prop.Value
    }
    if (-not $changed) { return }
    $colors.assignments = $newAssignments
    Save-WtwColors $colors
}
