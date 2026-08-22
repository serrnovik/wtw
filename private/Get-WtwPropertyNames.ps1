function Get-WtwPropertyNames {
    <#
    .SYNOPSIS
        Return an object's property names as an array, including for empty objects.
    .DESCRIPTION
        PowerShell's implicit `$Object.PSObject.Properties.Name` enumeration throws
        under strict mode when the property collection is empty. This helper always
        returns an array so callers can safely enumerate, count, and use `-contains`.

        Hashtables are handled separately: PowerShell only special-cases key access
        in the parser, so `PSObject.Properties` on a hashtable exposes the .NET
        surface (Count, Keys, Values, ...) and never the keys themselves.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Object
    )

    if ($null -eq $Object) {
        return ,@()
    }

    if ($Object -is [System.Collections.IDictionary]) {
        return ,@($Object.Keys | ForEach-Object { [string] $_ })
    }

    $names = @($Object.PSObject.Properties | ForEach-Object { $_.Name })
    return ,$names
}

function Get-WtwPropertyValue {
    <#
    .SYNOPSIS
        Read a possibly absent object property without violating strict mode.
    .DESCRIPTION
        Works for both PSCustomObject (registry/config JSON) and hashtable inputs.
        Hashtables need the explicit branch: `PSObject.Properties['key']` on a
        hashtable resolves against the .NET surface, not the keys, so every lookup
        would silently return $DefaultValue.
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

    if ($Object -is [System.Collections.IDictionary]) {
        if (-not $Object.Contains($Name)) {
            return $DefaultValue
        }
        return $Object[$Name]
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

function Get-WtwWorkspaceRecordedColor {
    <#
    .SYNOPSIS
        Read a workspace's recorded color without violating strict mode.
    .DESCRIPTION
        `wtw.color` is current; `peacock.color` is the pre-Peacock-exit fallback.
        The shipped minimal template has an empty settings object, so a dotted
        `settings.'wtw.color'` read throws under Set-StrictMode -Version Latest —
        which is `wtw init` of a repo that has no existing workspace yet.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Workspace
    )

    $settings = Get-WtwPropertyValue -Object $Workspace -Name 'settings'
    return (Get-WtwPropertyValue -Object $settings -Name 'wtw.color') ??
        (Get-WtwPropertyValue -Object $settings -Name 'peacock.color')
}
