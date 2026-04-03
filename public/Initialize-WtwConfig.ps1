function Initialize-WtwConfig {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Alias,

        [string] $WorkspacesDir
    )

    # Detect repo root
    $repoRoot = Resolve-WtwRepoRoot
    if (-not $repoRoot) {
        Write-Error 'Not inside a git repository.'
        return
    }

    $repoDir = Split-Path $repoRoot -Leaf
    # Strip trailing digits to get base name: snowmain3 -> snowmain
    $repoBaseName = $repoDir -replace '\d+$', ''
    if (-not $repoBaseName) { $repoBaseName = $repoDir }

    Write-Host "  Detected repo: $repoDir" -ForegroundColor Cyan
    Write-Host "  Base name:     $repoBaseName" -ForegroundColor Cyan
    Write-Host "  Path:          $repoRoot" -ForegroundColor Cyan

    # Session script
    $sessionScript = Get-WtwSessionScript $repoRoot
    if ($sessionScript) {
        Write-Host "  Session script: $sessionScript" -ForegroundColor Cyan
    } else {
        Write-Host '  Session script: (none found)' -ForegroundColor DarkGray
    }

    # Alias
    if (-not $Alias) {
        # Generate short alias: snowmain -> sn, everix -> evx
        $defaultAlias = if ($repoBaseName.Length -le 3) {
            $repoBaseName
        } else {
            # Take first 2-3 consonants or just first 2-3 chars
            $repoBaseName.Substring(0, [Math]::Min(3, $repoBaseName.Length))
        }
        $Alias = Read-Host "  Aliases (comma-separated) [$defaultAlias]"
        if (-not $Alias) { $Alias = $defaultAlias }
    }

    # Parse comma-separated aliases into array
    $aliasArray = @($Alias -split '[,\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    # Ensure config exists
    $config = Get-WtwConfig
    if (-not $config) {
        $config = New-WtwDefaultConfig
        if ($WorkspacesDir) {
            $config.workspacesDir = $WorkspacesDir
        }
        Save-WtwConfig $config
        Write-Host "  Created config: $(Join-Path $HOME '.wtw' 'config.json')" -ForegroundColor Green
    }

    # Find template workspace
    $wsDir = $config.workspacesDir.Replace('~', $HOME)
    $wsDir = [System.IO.Path]::GetFullPath($wsDir)
    $templateWs = $null
    if (Test-Path $wsDir) {
        $candidates = Get-ChildItem -Path $wsDir -Filter '*.code-workspace' | Where-Object {
            $_.BaseName -eq $repoDir -or $_.BaseName -eq $repoBaseName
        }
        if ($candidates) {
            $templateWs = $candidates[0].FullName
            Write-Host "  Template workspace: $templateWs" -ForegroundColor Cyan
        }
    }

    if (-not $templateWs) {
        Write-Host "  No workspace file found for '$repoDir' in $wsDir" -ForegroundColor Yellow
        Write-Host "  You can set templateWorkspace later in ~/.wtw/registry.json" -ForegroundColor DarkGray
    }

    # Register in registry
    $registry = Get-WtwRegistry
    $worktreeParent = Split-Path $repoRoot -Parent

    $repoEntry = [PSCustomObject]@{
        mainPath          = $repoRoot
        worktreeParent    = $worktreeParent
        sessionScript     = $sessionScript
        templateWorkspace = $templateWs
        aliases           = $aliasArray
        worktrees         = [PSCustomObject]@{}
    }

    # Preserve existing worktrees if re-initing
    if ($registry.repos.PSObject.Properties.Name -contains $repoBaseName) {
        $existing = $registry.repos.$repoBaseName
        if ($existing.worktrees) {
            $repoEntry.worktrees = $existing.worktrees
        }
    }

    $registry.repos | Add-Member -NotePropertyName $repoBaseName -NotePropertyValue $repoEntry -Force
    Save-WtwRegistry $registry

    # Record main color
    if ($templateWs -and (Test-Path $templateWs)) {
        $wsContent = Read-JsoncFile $templateWs
        if ($wsContent.settings.'peacock.color') {
            $mainColor = $wsContent.settings.'peacock.color'
            $colors = Get-WtwColors
            $colors.assignments | Add-Member -NotePropertyName "$repoBaseName/main" -NotePropertyValue $mainColor -Force
            Save-WtwColors $colors
            Write-Host "  Recorded main color: $mainColor" -ForegroundColor Cyan
        }
    }

    Write-Host ''
    Write-Host "  Registered '$repoBaseName' (aliases: $($aliasArray -join ', '))" -ForegroundColor Green
    Write-Host "  Run 'wtw create <task>' to create your first worktree." -ForegroundColor DarkGray
}
