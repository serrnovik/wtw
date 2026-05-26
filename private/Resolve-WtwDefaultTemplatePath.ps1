function Resolve-WtwDefaultTemplatePath {
    [CmdletBinding()]
    param()

    $moduleRoot = Split-Path $PSScriptRoot -Parent
    $templatePath = Join-Path $moduleRoot 'templates' 'minimal.code-workspace.template'
    if (Test-Path $templatePath) {
        return [System.IO.Path]::GetFullPath($templatePath)
    }

    return $null
}
