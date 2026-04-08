function Get-WtwSupersetColorName {
    # Map hex colors to Superset's named color palette
    param([string] $Hex)

    $colorMap = @{
        '#ef4444' = '#ef4444'; '#f97316' = '#f97316'; '#eab308' = '#eab308'
        '#22c55e' = '#22c55e'; '#14b8a6' = '#14b8a6'; '#3b82f6' = '#3b82f6'
        '#8b5cf6' = '#8b5cf6'; '#a855f7' = '#a855f7'; '#ec4899' = '#ec4899'
    }

    # Superset uses raw hex, so just pass through
    return $Hex
}
