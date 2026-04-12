<#
.SYNOPSIS
    Converts an integer RGB component to a two-digit lowercase hex string.

.DESCRIPTION
    Clamps the input to the range 0-255, then formats it as two hex digits (x2).

.PARAMETER Value
    Integer RGB component (clamped to 0-255).

.EXAMPLE
    ConvertTo-HexComponent -Value 200
    Returns 'c8'.

.NOTES
    No external dependencies.
#>
function ConvertTo-HexComponent {
    param([int] $Value)
    return ([math]::Max(0, [math]::Min(255, $Value))).ToString('x2')
}
