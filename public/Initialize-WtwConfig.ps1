function Initialize-WtwConfig {
    <#
    .SYNOPSIS
        Register the current repo with wtw.
    .DESCRIPTION
        Creates config, detects session script, sets up workspace template,
        and registers the repo in the wtw registry with alias and color assignment.
    .PARAMETER Alias
        Comma-separated aliases for the repo (e.g. "app,my-app").
    .PARAMETER WorkspacesDir
        Override the default directory where workspace files are stored.
    .PARAMETER Name
        Override the registry key (defaults to the repo directory name).
    .PARAMETER Template
        Alias or registry key of another repo, or path to a .template file
        to use as the workspace template source.
    .PARAMETER StartupScript
        Name of a PowerShell script in the repo root to run on session entry
        (e.g. "start-repository-session.ps1"). Overrides auto-detection.
        Worktrees inherit this from the parent repo.
    .EXAMPLE
        wtw init "app,my-app" --template ./workspace.template
        Register the current repo with aliases "app" and "my-app", using a local template file.
    .EXAMPLE
        wtw init "app" --startup-script start-repository-session.ps1
        Register with a custom session startup script.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Alias,

        [string] $WorkspacesDir,
        [string] $Name,
        [string] $Template,  # alias or registry key of repo, or path to .template file
        [string] $StartupScript
    )

    # Detect repo root
    $repoRoot = Resolve-WtwRepoRoot
    if (-not $repoRoot) {
        Write-Error 'Not inside a git repository.'
        return
    }

    $repoDir = Split-Path $repoRoot -Leaf
    $registryKey = if ($Name) { $Name } else { $repoDir }

    Write-Host "  Detected repo: $repoDir" -ForegroundColor Cyan
    Write-Host "  Registry key:  $registryKey" -ForegroundColor Cyan
    Write-Host "  Path:          $repoRoot" -ForegroundColor Cyan

    # Session script — explicit override or auto-detect
    $sessionScript = if ($StartupScript) {
        $StartupScript
    } else {
        Get-WtwSessionScript $repoRoot
    }
    if ($sessionScript) {
        Write-Host "  Session script: $sessionScript" -ForegroundColor Cyan
    } else {
        Write-Host '  Session script: (none — wtw will set terminal color/title directly)' -ForegroundColor DarkGray
    }

    # Alias
    if (-not $Alias) {
        $defaultAlias = $repoDir
        $Alias = Read-Host "  Aliases (comma-separated) [$defaultAlias]"
        if (-not $Alias) { $Alias = $defaultAlias }
    }

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

    # Alias collision check
    $registry = Get-WtwRegistry
    foreach ($existingName in $registry.repos.PSObject.Properties.Name) {
        if ($existingName -eq $registryKey) { continue }
        $existingRepo = $registry.repos.$existingName
        $existingAliases = Get-WtwRepoAliases $existingRepo
        foreach ($newAlias in $aliasArray) {
            if ($newAlias -in $existingAliases) {
                Write-Error "Alias '$newAlias' is already used by repo '$existingName'. Choose different aliases."
                return
            }
        }
        if ($registryKey -in $existingAliases) {
            Write-Error "Registry key '$registryKey' collides with an alias of repo '$existingName'."
            return
        }
    }

    # Resolve template source (the .template or .code-workspace file used for generation)
    $wsDir = $config.workspacesDir.Replace('~', $HOME)
    $wsDir = [System.IO.Path]::GetFullPath($wsDir)
    $templateSource = $null

    if ($Template) {
        # From another repo's template
        foreach ($rn in $registry.repos.PSObject.Properties.Name) {
            $r = $registry.repos.$rn
            if ($rn -eq $Template -or (Test-WtwAliasMatch $r $Template)) {
                $src = $r.template ?? $r.templateWorkspace
                if ($src -and (Test-Path $src)) {
                    $templateSource = $src
                    Write-Host "  Template from repo: $rn" -ForegroundColor Cyan
                }
                break
            }
        }
        # Or a direct file path
        if (-not $templateSource) {
            $candidatePath = [System.IO.Path]::GetFullPath($Template)
            if (Test-Path $candidatePath) {
                $templateSource = $candidatePath
            } else {
                Write-Warning "Could not resolve template '$Template'."
            }
        }
    }

    # Fallback: look for existing .code-workspace in workspacesDir
    if (-not $templateSource -and (Test-Path $wsDir)) {
        $candidates = Get-ChildItem -Path $wsDir -Filter '*.code-workspace' | Where-Object {
            $_.BaseName -eq $repoDir
        }
        if ($candidates) {
            $templateSource = $candidates[0].FullName
        }
    }

    if ($templateSource) {
        Write-Host "  Template source: $templateSource" -ForegroundColor Cyan
    } else {
        Write-Host "  No template found — workspace generation skipped." -ForegroundColor Yellow
        Write-Host "  You can set it later: wtw init --template <path>" -ForegroundColor DarkGray
    }

    # Pick/record main color
    $mainColor = New-WtwColor -RepoName $registryKey -TaskName 'main'
    # If existing workspace has a Peacock color, prefer that
    if ($templateSource -and (Test-Path $templateSource)) {
        $templateContent = Read-JsoncFile $templateSource
        if ($templateContent -and $templateContent.settings -and $templateContent.settings.'peacock.color') {
            $existingColor = $templateContent.settings.'peacock.color'
            # Only use it if this is the repo's own workspace (not a shared template)
            if (-not $Template) {
                $mainColor = $existingColor
                $colors = Get-WtwColors
                $colors.assignments | Add-Member -NotePropertyName "$registryKey/main" -NotePropertyValue $mainColor -Force
                Save-WtwColors $colors
            }
        }
    }
    Write-Host "  Color:         $mainColor" -ForegroundColor Cyan

    # Generate main workspace file from template
    $mainWorkspaceFile = $null
    if ($templateSource) {
        if (-not (Test-Path $wsDir)) {
            New-Item -Path $wsDir -ItemType Directory -Force | Out-Null
        }
        $mainWorkspaceFile = Join-Path $wsDir "${repoDir}.code-workspace"

        # Save registry first so New-WtwWorkspaceFile can resolve the repo
        $worktreeParent = Split-Path $repoRoot -Parent
        $repoEntry = [PSCustomObject]@{
            mainPath          = $repoRoot
            worktreeParent    = $worktreeParent
            sessionScript     = $sessionScript
            template          = $templateSource
            templateWorkspace = $mainWorkspaceFile
            aliases           = $aliasArray
            worktrees         = [PSCustomObject]@{}
        }
        if ($registry.repos.PSObject.Properties.Name -contains $registryKey) {
            $existing = $registry.repos.$registryKey
            if ($existing.worktrees) { $repoEntry.worktrees = $existing.worktrees }
        }
        $registry.repos | Add-Member -NotePropertyName $registryKey -NotePropertyValue $repoEntry -Force
        Save-WtwRegistry $registry

        New-WtwWorkspaceFile `
            -RepoName $registryKey `
            -Name $repoDir `
            -CodeFolderPath $repoRoot `
            -TemplatePath $templateSource `
            -OutputPath $mainWorkspaceFile `
            -Color $mainColor `
            -Managed | Out-Null

        Write-Host "  Workspace:     $mainWorkspaceFile" -ForegroundColor Green
    } else {
        # No template — just register without workspace
        $worktreeParent = Split-Path $repoRoot -Parent
        $repoEntry = [PSCustomObject]@{
            mainPath          = $repoRoot
            worktreeParent    = $worktreeParent
            sessionScript     = $sessionScript
            template          = $null
            templateWorkspace = $null
            aliases           = $aliasArray
            worktrees         = [PSCustomObject]@{}
        }
        if ($registry.repos.PSObject.Properties.Name -contains $registryKey) {
            $existing = $registry.repos.$registryKey
            if ($existing.worktrees) { $repoEntry.worktrees = $existing.worktrees }
        }
        $registry.repos | Add-Member -NotePropertyName $registryKey -NotePropertyValue $repoEntry -Force
        Save-WtwRegistry $registry
    }

    Write-Host ''
    Write-Host "  Registered '$registryKey' (aliases: $($aliasArray -join ', '))" -ForegroundColor Green
    if ($Template) {
        Write-Host "  Template shared from: $Template" -ForegroundColor DarkGray
    }
    Write-Host "  Run 'wtw create <task>' to create your first worktree." -ForegroundColor DarkGray
}
