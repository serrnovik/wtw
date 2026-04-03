function New-WtwWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,

        [string] $WorktreePath,
        [string] $Repo,
        [switch] $Main,
        [string] $CodeFolder,
        [switch] $Open
    )

    $repoName, $repoEntry = Resolve-WtwRepo -RepoAlias $Repo
    if (-not $repoName) { return }

    $config = Get-WtwConfig
    if (-not $config) {
        Write-Error 'wtw not initialized. Run "wtw init" first.'
        return
    }

    if (-not $repoEntry.templateWorkspace -or -not (Test-Path $repoEntry.templateWorkspace)) {
        Write-Error "No template workspace configured for $repoName."
        return
    }

    # Determine code folder path
    $codeFolderPath = if ($CodeFolder) {
        [System.IO.Path]::GetFullPath($CodeFolder)
    } elseif ($Main) {
        $repoEntry.mainPath
    } elseif ($WorktreePath) {
        [System.IO.Path]::GetFullPath($WorktreePath)
    } else {
        # Try to find existing worktree by name
        if ($repoEntry.worktrees.PSObject.Properties.Name -contains $Name) {
            $repoEntry.worktrees.$Name.path
        } else {
            # Check if path exists as sibling
            $candidate = Join-Path $repoEntry.worktreeParent "${repoName}_${Name}"
            if (Test-Path $candidate) {
                $candidate
            } else {
                Write-Error "Cannot determine code folder. Use --worktree-path, --code-folder, or --main."
                return
            }
        }
    }

    if (-not (Test-Path $codeFolderPath)) {
        Write-Error "Code folder does not exist: $codeFolderPath"
        return
    }

    $wsDir = $config.workspacesDir.Replace('~', $HOME)
    $wsDir = [System.IO.Path]::GetFullPath($wsDir)
    $wsName = if ($Main) { "${repoName}_main" } else { "${repoName}_${Name}" }
    $wsFile = Join-Path $wsDir "${wsName}.code-workspace"

    # Pick color
    $taskKey = if ($Main) { 'main' } else { $Name }
    $color = New-WtwColor -RepoName $repoName -TaskName $taskKey

    Write-Host ''
    Write-Host "  Generating workspace: $wsName" -ForegroundColor Cyan
    Write-Host "  Code folder: $codeFolderPath"
    Write-Host "  Color:       $color"

    New-WtwWorkspaceFile `
        -RepoName $repoName `
        -Name $wsName `
        -CodeFolderPath $codeFolderPath `
        -TemplatePath $repoEntry.templateWorkspace `
        -OutputPath $wsFile `
        -Color $color `
        -Managed | Out-Null

    Write-Host "  Workspace:   $wsFile" -ForegroundColor Green

    if ($Open) {
        $editor = $config.editor ?? 'code'
        Write-Host "  Opening in ${editor}..." -ForegroundColor Green
        & $editor $wsFile
    }

    Write-Host ''
}
