# wtw — Git Worktree + Workspace Manager
# Module loader: dot-source public/ and private/ functions

$dotSourceParams = @{
    Filter      = '*.ps1'
    Recurse     = $true
    ErrorAction = 'Stop'
}

$public = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'public') @dotSourceParams)
$private = @()
$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'private'
if (Test-Path $privatePath) {
    $private = @(Get-ChildItem -Path $privatePath @dotSourceParams)
}

foreach ($import in @($public + $private)) {
    try {
        . $import.FullName
    } catch {
        throw "Unable to dot source [$($import.FullName)]"
    }
}

Export-ModuleMember -Function $public.BaseName

Set-Alias -Name wtw -Value Invoke-Wtw -Scope Global -Force
Export-ModuleMember -Alias wtw

# Load tab completion
$completionPath = Join-Path $PSScriptRoot 'completions' 'wtw.auto-completion.ps1'
if (Test-Path $completionPath) {
    . $completionPath
}
