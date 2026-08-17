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

function Get-WtwVisibleStringLength {
    <#
    .SYNOPSIS
        Length of a string as displayed in a terminal (ANSI SGR sequences stripped).
    #>
    param([string] $Text)
    if ([string]::IsNullOrEmpty($Text)) {
        return 0
    }
    $esc = [regex]::Escape([char]27)
    $stripped = [regex]::Replace($Text, "$esc\[[0-9;]*m", '')
    return $stripped.Length
}

function Split-WtwTableCellIntoLines {
    <#
    .NOTES
        Do not use `-split "`n", [StringSplitOptions]::None` — in PowerShell the second
        -split operand is *max substrings* (int); None = 0 and breaks the split, leaving a
        scalar string so `$s[$i]` indexes chars and PadRight fails.
    #>
    param([string] $Value)
    if ($null -eq $Value) {
        return @('')
    }
    $normalized = "$Value"
    if ($normalized -eq '') {
        return @('')
    }
    $parts = $normalized.Split("`n", [StringSplitOptions]::None)
    return [string[]]$parts
}

function ConvertTo-WtwTableCellLineArray {
    <#
    .SYNOPSIS
        Ensures a cell line collection is a string[] (scalar string → one row, never char-wise).
    #>
    param($CellLines)
    if ($null -eq $CellLines) {
        return @('')
    }
    if ($CellLines -is [string]) {
        return @([string]$CellLines)
    }
    return [string[]]@($CellLines | ForEach-Object { "$_" })
}

<#
.SYNOPSIS
    Prints a table of objects to the host with aligned columns.

.DESCRIPTION
    Computes column widths, writes a header and separator, then each row. When a column
    is named 'Color' and the value matches a six-digit hex, Format-WtwColorSwatch is used.
    Cell values may contain newline (`n) characters; each line stacks in the same column.

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
        # AllowEmptyCollection: a Mandatory [array] rejects @() at bind time
        # ("cannot bind argument ... empty array"), so filtering down to nothing
        # — e.g. `wtw list detailed`, where 'detailed' binds as a repo name —
        # crashed here instead of printing the "(none)" line below.
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyCollection()]
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

    $columnSeparatorWidth = 2

    # Calculate column widths (support multiline cells; Color uses visible swatch width)
    $widths = @{}
    foreach ($col in $Columns) {
        $widths[$col] = [Math]::Max($col.Length, 0)
        foreach ($item in $Items) {
            $val = "$($item.$col)"
            $cellLines = @(ConvertTo-WtwTableCellLineArray (Split-WtwTableCellIntoLines $val))
            $isHexColorCell = $col -eq 'Color' -and $cellLines.Count -eq 1 -and $val -match '^#[0-9a-fA-F]{6}$'
            if ($isHexColorCell) {
                $swatchText = Format-WtwColorSwatch $val
                $visibleSwatchWidth = Get-WtwVisibleStringLength $swatchText
                $candidateWidth = [Math]::Max($val.Length, $visibleSwatchWidth)
                if ($candidateWidth -gt $widths[$col]) {
                    $widths[$col] = $candidateWidth
                }
                continue
            }
            foreach ($line in (ConvertTo-WtwTableCellLineArray (Split-WtwTableCellIntoLines $val))) {
                $lineLength = "$line".Length
                if ($lineLength -gt $widths[$col]) {
                    $widths[$col] = $lineLength
                }
            }
        }
    }

    # Header
    $header = ($Columns | ForEach-Object { $_.PadRight($widths[$_]) }) -join (' ' * $columnSeparatorWidth)
    Write-Host "  $header" -ForegroundColor Cyan
    $sep = ($Columns | ForEach-Object { '-' * $widths[$_] }) -join (' ' * $columnSeparatorWidth)
    Write-Host "  $sep" -ForegroundColor DarkGray

    # Rows (each logical row may span multiple terminal lines)
    foreach ($item in $Items) {
        $columnLineArrays = [ordered]@{}
        $maxLineCount = 1
        foreach ($col in $Columns) {
            $val = "$($item.$col)"
            $linesPreview = @(ConvertTo-WtwTableCellLineArray (Split-WtwTableCellIntoLines $val))
            $hexColorForCell = $col -eq 'Color' -and $linesPreview.Count -eq 1 -and $val -match '^#[0-9a-fA-F]{6}$'
            if ($hexColorForCell) {
                $columnLineArrays[$col] = @([string]$val)
            } else {
                $lines = @(ConvertTo-WtwTableCellLineArray (Split-WtwTableCellIntoLines $val))
                $columnLineArrays[$col] = $lines
                if ($lines.Count -gt $maxLineCount) {
                    $maxLineCount = $lines.Count
                }
            }
        }

        for ($lineIndex = 0; $lineIndex -lt $maxLineCount; $lineIndex++) {
            $segments = [System.Collections.Generic.List[string]]::new()
            foreach ($col in $Columns) {
                $linesForColumn = @(ConvertTo-WtwTableCellLineArray $columnLineArrays[$col])
                $hexColorForCell = $col -eq 'Color' -and $linesForColumn.Count -eq 1 -and ($linesForColumn[0] -match '^#[0-9a-fA-F]{6}$')
                if ($hexColorForCell) {
                    if ($lineIndex -eq 0) {
                        $swatchText = Format-WtwColorSwatch $linesForColumn[0]
                        $padToWidth = $widths[$col] - (Get-WtwVisibleStringLength $swatchText)
                        if ($padToWidth -gt 0) {
                            $segments.Add($swatchText + (' ' * $padToWidth))
                        } else {
                            $segments.Add($swatchText)
                        }
                    } else {
                        $segments.Add(' ' * $widths[$col])
                    }
                    continue
                }

                $pieceText = if ($lineIndex -lt $linesForColumn.Count) { [string]$linesForColumn[$lineIndex] } else { '' }
                $segments.Add($pieceText.PadRight($widths[$col]))
            }
            $rowText = ($segments.ToArray() -join (' ' * $columnSeparatorWidth))
            Write-Host "  $rowText"
        }
    }
}
