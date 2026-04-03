$script:WtwConfigDir = Join-Path $HOME '.wtw'
$script:WtwConfigPath = Join-Path $script:WtwConfigDir 'config.json'

function Get-WtwConfig {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:WtwConfigPath)) {
        return $null
    }
    return Get-Content -Path $script:WtwConfigPath -Raw | ConvertFrom-Json
}

function Save-WtwConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [PSObject] $Config
    )

    if (-not (Test-Path $script:WtwConfigDir)) {
        New-Item -Path $script:WtwConfigDir -ItemType Directory -Force | Out-Null
    }
    $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:WtwConfigPath -Encoding utf8
}

function New-WtwDefaultConfig {
    [CmdletBinding()]
    param()

    $workspacesDir = if ($IsWindows) {
        Join-Path $HOME 'Data' 'code-workspaces'
    } else {
        Join-Path $HOME 'Data' 'code-workspaces'
    }

    return [PSCustomObject]@{
        editor             = 'cursor'
        workspacesDir      = $workspacesDir
        staleWorktreePaths = @(
            (Join-Path $HOME '.codex' 'worktrees'),
            (Join-Path $HOME '.cursor' 'worktrees'),
            (Join-Path $HOME '.superset' 'worktrees'),
            (Join-Path $HOME 'conductor' 'workspaces')
        )
    }
}
