function New-WtwWorktree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Task,

        [string] $Branch,
        [string] $Repo,
        [switch] $Open,
        [switch] $NoBranch
    )

    $repoName, $repoEntry = Resolve-WtwRepo -RepoAlias $Repo
    if (-not $repoName) { return }

    # Check if task already exists
    if ($repoEntry.worktrees.PSObject.Properties.Name -contains $Task) {
        Write-Error "Worktree '$Task' already exists for $repoName. Use 'wtw go $Task' or 'wtw remove $Task' first."
        return
    }

    $worktreePath = Join-Path $repoEntry.worktreeParent "${repoName}_${Task}"

    if (Test-Path $worktreePath) {
        Write-Error "Path already exists: $worktreePath"
        return
    }

    # Branch name
    if (-not $Branch) {
        $Branch = $Task
    }

    # Create git worktree
    Write-Host "  Creating worktree..." -ForegroundColor Cyan
    $mainRepo = $repoEntry.mainPath

    if ($NoBranch) {
        # Attach to existing branch
        $result = git -C $mainRepo worktree add $worktreePath $Branch 2>&1
    } else {
        # Create new branch
        $result = git -C $mainRepo worktree add -b $Branch $worktreePath 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Error "git worktree add failed: $result"
        return
    }

    Write-Host "  Worktree: $worktreePath" -ForegroundColor Green
    Write-Host "  Branch:   $Branch" -ForegroundColor Green

    # Pick color
    $color = New-WtwColor -RepoName $repoName -TaskName $Task
    Write-Host "  Color:    $color" -ForegroundColor Green

    # Generate workspace file
    $wsFile = $null
    $config = Get-WtwConfig
    if ($config -and $repoEntry.templateWorkspace -and (Test-Path $repoEntry.templateWorkspace)) {
        $wsDir = $config.workspacesDir.Replace('~', $HOME)
        $wsDir = [System.IO.Path]::GetFullPath($wsDir)
        $wsFileName = "${repoName}_${Task}.code-workspace"
        $wsFile = Join-Path $wsDir $wsFileName

        # Read template
        $template = Read-JsoncFile $repoEntry.templateWorkspace

        # Replace first folder (the code folder)
        if ($template.folders -and $template.folders.Count -gt 0) {
            $template.folders[0].path = $worktreePath
            $template.folders[0].name = "${repoName}_${Task}"
        }

        # Replace ${workspaceFolder:X} references in settings
        $repoDir = Split-Path $repoEntry.mainPath -Leaf
        $newFolderName = "${repoName}_${Task}"
        $json = $template | ConvertTo-Json -Depth 20
        $json = $json -replace [regex]::Escape("`${workspaceFolder:$repoDir}"), "`${workspaceFolder:$newFolderName}"

        # Re-parse to inject colors
        $workspace = $json | ConvertFrom-Json

        # Inject Peacock color block
        $peacockBlock = ConvertTo-PeacockColorBlock $color
        $colorCustomizations = [PSCustomObject]$peacockBlock
        $workspace.settings | Add-Member -NotePropertyName 'workbench.colorCustomizations' -NotePropertyValue $colorCustomizations -Force
        $workspace.settings | Add-Member -NotePropertyName 'peacock.color' -NotePropertyValue $color -Force

        # Add wtw metadata
        $workspace.settings | Add-Member -NotePropertyName 'wtw.managed' -NotePropertyValue $true -Force
        $workspace.settings | Add-Member -NotePropertyName 'wtw.repo' -NotePropertyValue $repoName -Force
        $workspace.settings | Add-Member -NotePropertyName 'wtw.task' -NotePropertyValue $Task -Force
        $workspace.settings | Add-Member -NotePropertyName 'wtw.branch' -NotePropertyValue $Branch -Force
        $workspace.settings | Add-Member -NotePropertyName 'wtw.worktreePath' -NotePropertyValue $worktreePath -Force
        $workspace.settings | Add-Member -NotePropertyName 'wtw.templateSource' -NotePropertyValue $repoEntry.templateWorkspace -Force
        $workspace.settings | Add-Member -NotePropertyName 'wtw.generatedAt' -NotePropertyValue (Get-Date -Format 'o') -Force

        # Write workspace file
        $workspace | ConvertTo-Json -Depth 20 | Set-Content -Path $wsFile -Encoding utf8
        Write-Host "  Workspace: $wsFile" -ForegroundColor Green
    } else {
        Write-Host '  Workspace: (no template configured, skipped)' -ForegroundColor Yellow
    }

    # Register in registry
    $registry = Get-WtwRegistry
    $wtEntry = [PSCustomObject]@{
        path      = $worktreePath
        branch    = $Branch
        workspace = $wsFile
        color     = $color
        created   = (Get-Date -Format 'o')
    }
    $registry.repos.$repoName.worktrees | Add-Member -NotePropertyName $Task -NotePropertyValue $wtEntry -Force
    Save-WtwRegistry $registry

    # Open?
    if ($Open) {
        Open-WtwWorkspace -Name $Task -Repo $repoName
    }

    Write-Host ''
    Write-Host "  Done! Use 'wtw go $Task' to switch." -ForegroundColor Green
}
