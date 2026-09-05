function Get-WtwExternalBackupRoot {
    <#
    .SYNOPSIS
        Directory that stores rotating backups of external-tool configs.
    .DESCRIPTION
        Default: ~/.wtw/backups. Tests override $script:WtwBackupRoot.
    #>
    $override = Get-Variable -Name WtwBackupRoot -Scope Script -ErrorAction SilentlyContinue
    if ($override -and $override.Value) { return $override.Value }
    if ($env:WTW_BACKUP_ROOT) { return $env:WTW_BACKUP_ROOT }
    return Join-Path $HOME '.wtw' 'backups'
}

function Backup-WtwExternalConfig {
    <#
    .SYNOPSIS
        Copy an external-system config into ~/.wtw/backups/<system>/ before wtw writes it.
    .DESCRIPTION
        No-ops when the source file is missing. After the copy, prunes that
        file's backup set to: the 3 newest copies, plus the newest copy that is
        at least 3 / 7 / 30 days old.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Alias('System')]
        [string] $Tool,

        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Label
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $safeSystem = ($Tool -replace '[^A-Za-z0-9._-]', '_').Trim('_')
    if (-not $safeSystem) { $safeSystem = 'misc' }

    $leaf = if ($Label) { $Label } else { Split-Path -Path $Path -Leaf }
    $safeLeaf = ($leaf -replace '[^A-Za-z0-9._-]', '_').Trim('_')
    if (-not $safeLeaf) { $safeLeaf = 'config' }

    $dir = Join-Path (Get-WtwExternalBackupRoot) $safeSystem
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $dest = Join-Path $dir "$safeLeaf.$stamp.bak"
    Copy-Item -LiteralPath $Path -Destination $dest -Force

    Clear-WtwExternalConfigBackups -Directory $dir -LeafPrefix $safeLeaf
    return $dest
}

function Clear-WtwExternalConfigBackups {
    <#
    .SYNOPSIS
        Keep the last 3 backups plus one snapshot each at 3 / 7 / 30 days.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Directory,

        [Parameter(Mandatory)]
        [string] $LeafPrefix
    )

    if (-not (Test-Path -LiteralPath $Directory)) { return }

    $files = @(
        Get-ChildItem -LiteralPath $Directory -File -Filter "$LeafPrefix.*.bak" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )
    if ($files.Count -eq 0) { return }

    $keep = @{}
    foreach ($recent in ($files | Select-Object -First 3)) {
        $keep[$recent.FullName] = $true
    }

    $now = Get-Date
    foreach ($days in 3, 7, 30) {
        $cutoff = $now.AddDays(-$days)
        $aged = @(
            $files |
                Where-Object { $_.LastWriteTime -le $cutoff } |
                Select-Object -First 1
        )
        if ($aged.Count -gt 0) {
            $keep[$aged[0].FullName] = $true
        }
    }

    foreach ($file in $files) {
        if (-not $keep.ContainsKey($file.FullName)) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}
