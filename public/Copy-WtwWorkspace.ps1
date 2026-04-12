function Copy-WtwWorkspace {
    <#
    .SYNOPSIS
        Create a standalone (unmanaged) copy of a workspace from template.
    .DESCRIPTION
        Unlike New-WtwWorkspace, the copy is not tracked by wtw sync. It resolves
        template placeholders into a concrete workspace file with a fresh color
        assignment, but writes no wtw.managed metadata.
    .PARAMETER Name
        Name for the new workspace file (used as filename and display label).
    .PARAMETER Repo
        Repo alias or name to copy from. Resolved via the wtw registry.
    .PARAMETER CodeFolder
        Override the code folder path instead of using the repo main path.
    .PARAMETER Open
        Open the workspace in the configured editor after creation.
    .EXAMPLE
        wtw copy playground --repo app
        Creates an unmanaged workspace named "playground" from the "app" repo template.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,

        [string] $Repo,
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

    # Code folder defaults to main repo
    $codeFolderPath = if ($CodeFolder) {
        [System.IO.Path]::GetFullPath($CodeFolder)
    } else {
        $repoEntry.mainPath
    }

    $wsDir = $config.workspacesDir.Replace('~', $HOME)
    $wsDir = [System.IO.Path]::GetFullPath($wsDir)
    $wsFile = Join-Path $wsDir "${Name}.code-workspace"

    if (Test-Path $wsFile) {
        Write-Error "File already exists: $wsFile. Remove it first or choose a different name."
        return
    }

    # Full concrete copy — no wtw.managed metadata, just resolved placeholders
    $color = New-WtwColor -RepoName $repoName -TaskName $Name

    Write-Host ''
    Write-Host "  Copying workspace: $Name" -ForegroundColor Cyan
    Write-Host "  Code folder: $codeFolderPath"
    Write-Host "  Color:       $color"

    New-WtwWorkspaceFile `
        -RepoName $repoName `
        -Name $Name `
        -CodeFolderPath $codeFolderPath `
        -TemplatePath $repoEntry.templateWorkspace `
        -OutputPath $wsFile `
        -Color $color | Out-Null
    # Note: no -Managed flag — standalone copy

    Write-Host "  Created:     $wsFile" -ForegroundColor Green

    if ($Open) {
        $editor = $config.editor ?? 'code'
        Write-Host "  Opening in ${editor}..." -ForegroundColor Green
        & $editor $wsFile
    }

    Write-Host ''
}
