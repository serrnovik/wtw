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
        $row = ($Columns | ForEach-Object { "$($item.$_)".PadRight($widths[$_]) }) -join '  '
        Write-Host "  $row"
    }
}
