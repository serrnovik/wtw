function New-WtwWorkspace {
    <#
    .SYNOPSIS
        Generate a workspace file without creating a git worktree.
    .DESCRIPTION
        Creates a VS Code workspace file for a repo or worktree using the
        configured template, without creating a new git worktree. Useful for
        adding workspace files to existing worktrees or the main repo.
    .PARAMETER Name
        Target name for the workspace (task name or identifier).
    .PARAMETER WorktreePath
        Path to an existing worktree directory to use as the code folder.
    .PARAMETER Repo
        Parent repo alias or name.
    .PARAMETER Main
        Generate a workspace for the main repo instead of a worktree.
    .PARAMETER CodeFolder
        Override the code folder path in the workspace file.
    .PARAMETER Open
        Open the workspace in the configured editor after generation.
    .EXAMPLE
        wtw workspace my-feature --repo app
        Generate a workspace file for "my-feature" under the "app" repo.
    #>
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
