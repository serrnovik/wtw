function Copy-WtwWorkspace {
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
