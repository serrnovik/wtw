function Get-WtwPropertyNames {
    <#
    .SYNOPSIS
        Return an object's property names as an array, including for empty objects.
    .DESCRIPTION
        PowerShell's implicit `$Object.PSObject.Properties.Name` enumeration throws
        under strict mode when the property collection is empty. This helper always
        returns an array so callers can safely enumerate, count, and use `-contains`.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Object
    )

    if ($null -eq $Object) {
        return ,@()
    }

    $names = @($Object.PSObject.Properties | ForEach-Object { $_.Name })
    return ,$names
}

function Get-WtwPropertyValue {
    <#
    .SYNOPSIS
        Read a possibly absent object property without violating strict mode.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Object,

        [Parameter(Mandatory)]
        [string] $Name,

        [AllowNull()]
        [object] $DefaultValue = $null
    )

    if ($null -eq $Object) {
        return $DefaultValue
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}
