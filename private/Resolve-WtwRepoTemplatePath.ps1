function Resolve-WtwRepoTemplatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoRoot
    )

    $templatesDir = Join-Path $RepoRoot 'configs' 'workspace-templates'
    if (-not (Test-Path $templatesDir)) {
        return $null
    }

    $repoDir = Split-Path $RepoRoot -Leaf
    $repoStem = $repoDir -replace '\d+$', ''
    $preferredNames = @(
        "$repoDir.code-workspace.template",
        "$repoDir.code-workspace"
    )

    if ($repoStem -and $repoStem -ne $repoDir) {
        $preferredNames += @(
            "$repoStem.code-workspace.template",
            "$repoStem.code-workspace"
        )
    }

    foreach ($name in $preferredNames) {
        $candidate = Join-Path $templatesDir $name
        if (Test-Path $candidate) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    $templates = @(Get-ChildItem -Path $templatesDir -File | Where-Object {
        $_.Name -like '*.code-workspace.template' -or $_.Name -like '*.code-workspace'
    })
    if ($templates.Count -eq 1) {
        return $templates[0].FullName
    }

    return $null
}
