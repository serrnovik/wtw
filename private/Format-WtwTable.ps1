<#
.SYNOPSIS
    Renders a hex color as an ANSI true-color swatch with contrasting foreground text.

.DESCRIPTION
    Validates '#RRGGBB', then emits escape sequences for 24-bit foreground and background.
    Used by Format-WtwTable for the Color column.

.PARAMETER Hex
    Six-digit hex color including leading '#'.

.EXAMPLE
    Format-WtwColorSwatch -Hex '#e05d44'
    Returns an ANSI-colored string showing the hex value on a colored background.

.NOTES
    Depends on: Get-ContrastForeground
#>
function Format-WtwColorSwatch {
    param([string] $Hex)
    if ($Hex -notmatch '^#[0-9a-fA-F]{6}$') { return $Hex }
    $r = [convert]::ToInt32($Hex.Substring(1, 2), 16)
    $g = [convert]::ToInt32($Hex.Substring(3, 2), 16)
    $b = [convert]::ToInt32($Hex.Substring(5, 2), 16)
    $fg = Get-ContrastForeground $Hex
    $fr = [convert]::ToInt32($fg.Substring(1, 2), 16)
    $fg2 = [convert]::ToInt32($fg.Substring(3, 2), 16)
    $fb = [convert]::ToInt32($fg.Substring(5, 2), 16)
    $esc = [char]27
    # Render: colored block with hex text inside
    return "${esc}[38;2;${fr};${fg2};${fb}m${esc}[48;2;${r};${g};${b}m ${Hex} ${esc}[0m"
}

<#
.SYNOPSIS
    Prints a table of objects to the host with aligned columns.

.DESCRIPTION
    Computes column widths, writes a header and separator, then each row. When a column
    is named 'Color' and the value matches a six-digit hex, Format-WtwColorSwatch is used.

.PARAMETER Items
    Array of objects (e.g., PSCustomObject rows) to display.

.PARAMETER Columns
    Optional ordered list of property names to show. Defaults to all properties of the first item.

.EXAMPLE
    Format-WtwTable -Items $rows -Columns @('Name', 'Color')

.NOTES
    Depends on: Format-WtwColorSwatch (when Color column holds a hex value)
#>
function Format-WtwTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [array] $Items,

        [Parameter(Position = 1)]
        [string[]] $Columns
    )

    if ($Items.Count -eq 0) {
        Write-Host '  (none)' -ForegroundColor DarkGray
        return
    }

    if (-not $Columns) {
        $Columns = $Items[0].PSObject.Properties.Name
    }

    # Calculate column widths
    $widths = @{}
    foreach ($col in $Columns) {
        $widths[$col] = $col.Length
        foreach ($item in $Items) {
            $val = "$($item.$col)"
            if ($val.Length -gt $widths[$col]) {
                $widths[$col] = $val.Length
            }
        }
    }

    # Header
    $header = ($Columns | ForEach-Object { $_.PadRight($widths[$_]) }) -join '  '
    Write-Host "  $header" -ForegroundColor Cyan
    $sep = ($Columns | ForEach-Object { '-' * $widths[$_] }) -join '  '
    Write-Host "  $sep" -ForegroundColor DarkGray

    # Rows
    foreach ($item in $Items) {
        $segments = @()
        foreach ($col in $Columns) {
            $val = "$($item.$col)"
            $padded = $val.PadRight($widths[$col])
            if ($col -eq 'Color' -and $val -match '^#[0-9a-fA-F]{6}$') {
                $segments += Format-WtwColorSwatch $val
                # Swatch visible width = val.Length + 2 (spaces around hex), compensate
                $extra = $widths[$col] - $val.Length - 2
                if ($extra -gt 0) { $segments += ' ' * $extra }
            } else {
                $segments += $padded
            }
        }
        $row = $segments -join '  '
        Write-Host "  $row"
    }
}
