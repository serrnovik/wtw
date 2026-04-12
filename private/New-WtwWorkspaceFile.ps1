function New-WtwWorkspaceFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoName,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $CodeFolderPath,

        [Parameter(Mandatory)]
        [string] $TemplatePath,

        [Parameter(Mandatory)]
        [string] $OutputPath,

        [string] $Color,
        [string] $Branch,
        [string] $WorktreePath,
        [switch] $Managed
    )

    if (-not (Test-Path $TemplatePath)) {
        Write-Error "Template not found: $TemplatePath"
        return $null
    }

    $raw = Get-Content -Path $TemplatePath -Raw -ErrorAction Stop
    $isTemplate = $raw -match '\{\{WTW_'

    if ($isTemplate) {
        # New-style template with {{WTW_*}} placeholders
        $json = $raw
        $json = $json -replace '\{\{WTW_WORKSPACE_NAME\}\}', $Name
        $json = $json -replace '\{\{WTW_CODE_FOLDER\}\}', ($CodeFolderPath -replace '\\', '\\')
        $workspace = $json | ConvertFrom-Json
    } else {
        # Legacy: real workspace file - regex replace folder[0] and ${workspaceFolder:X}
        # Strip JSONC artifacts
        $cleaned = $raw -replace '(?m)^\s*//.*$', ''
        $cleaned = $cleaned -replace ',\s*([\}\]])', '$1'
        $template = $cleaned | ConvertFrom-Json

        if ($template.folders -and $template.folders.Count -gt 0) {
            $template.folders[0].path = $CodeFolderPath
            $template.folders[0].name = $Name
        }

        # Replace ${workspaceFolder:X} references
        $registry = Get-WtwRegistry
        $repoEntry = $registry.repos.$RepoName
        $oldFolderName = if ($repoEntry) { Split-Path $repoEntry.mainPath -Leaf } else { $null }

        $json = $template | ConvertTo-Json -Depth 20
        if ($oldFolderName) {
            $json = $json -replace [regex]::Escape("`${workspaceFolder:$oldFolderName}"), "`${workspaceFolder:$Name}"
        }
        $workspace = $json | ConvertFrom-Json
    }

    # Inject Peacock color block if color provided
    if ($Color) {
        $peacockBlock = ConvertTo-PeacockColorBlock $Color
        $colorCustomizations = [PSCustomObject]$peacockBlock
        $workspace.settings | Add-Member -NotePropertyName 'workbench.colorCustomizations' -NotePropertyValue $colorCustomizations -Force
        $workspace.settings | Add-Member -NotePropertyName 'peacock.color' -NotePropertyValue $Color -Force
    }

    # Add wtw metadata
    if ($Managed) {
        $workspace.settings | Add-Member -NotePropertyName 'wtw.managed' -NotePropertyValue $true -Force
        $workspace.settings | Add-Member -NotePropertyName 'wtw.repo' -NotePropertyValue $RepoName -Force
        $workspace.settings | Add-Member -NotePropertyName 'wtw.task' -NotePropertyValue $Name -Force
        $workspace.settings | Add-Member -NotePropertyName 'wtw.templateSource' -NotePropertyValue $TemplatePath -Force
        $workspace.settings | Add-Member -NotePropertyName 'wtw.generatedAt' -NotePropertyValue (Get-Date -Format 'o') -Force
        if ($Branch) {
            $workspace.settings | Add-Member -NotePropertyName 'wtw.branch' -NotePropertyValue $Branch -Force
        }
        if ($WorktreePath) {
            $workspace.settings | Add-Member -NotePropertyName 'wtw.worktreePath' -NotePropertyValue $WorktreePath -Force
        }
    }

    # Write
    $workspace | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputPath -Encoding utf8
    return $OutputPath
}
