function Get-WtwWindowTitle {
    <#
    .SYNOPSIS
        Build a terminal window/tab title string for a git repository session.
    .DESCRIPTION
        Derives a deterministic icon from the repo root path and the current branch
        name via FNV hash. Title order: "#PR | branch-icon branch | folder-icon folder".
        Environment prefixes (DEV / UAT / PROD / Leyton / CF) are prepended based on
        the repo root path. Admin and custom label are prepended last.
    .PARAMETER RepoRoot
        Absolute path to the repository root. Defaults to the current directory.
    .PARAMETER FolderName
        Display name for the repository folder. Derived from RepoRoot when omitted.
    .PARAMETER PrNumber
        Open PR number. Prepended as "#N | " when present.
    .PARAMETER IsAdmin
        Prepends a policeman icon when set.
    .PARAMETER Label
        Free-text label prepended before all other segments.
    .EXAMPLE
        Get-WtwWindowTitle -RepoRoot $PSScriptRoot -PrNumber 42
    #>
    [CmdletBinding()]
    param(
        [string] $RepoRoot   = $PWD.Path,
        [string] $FolderName,
        [string] $PrNumber,
        [switch] $IsAdmin,
        [string] $Label
    )

    if (-not $FolderName) { $FolderName = Split-Path $RepoRoot -Leaf }

    $icons = @(Get-WtwIconPool)
    if ($icons.Count -eq 0) {
        $icons = @('💠', '🔶', '🔷', '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓')
    }
    $folderIcon = $icons[(Get-WtwNumberFromRange $icons.Length (Get-WtwFNVHash $RepoRoot))]

    try {
        $branch = git -C $RepoRoot rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) { throw }
        $branchIcon = if ($branch -ne 'develop') {
            $icons[(Get-WtwNumberFromRange $icons.Length (Get-WtwFNVHash $branch))]
        } else { '❗❗' }
        $title = "$branchIcon $branch | $folderIcon $FolderName"
    } catch {
        $title = "$folderIcon $FolderName"
    }

    if ($RepoRoot -match '[/\\]dev[/\\]'    -or $RepoRoot -match '[/\\]dev$')    { $title = "🧪 DEV | $title" }
    if ($RepoRoot -match '[/\\]uat[/\\]'    -or $RepoRoot -match '[/\\]uat$')    { $title = "🔬 UAT | $title" }
    if ($RepoRoot -match '[/\\]prod[/\\]'   -or $RepoRoot -match '[/\\]prod$')   { $title = "❗❗ PROD | $title" }
    if ($RepoRoot -match '[/\\]leyton[/\\]' -or $RepoRoot -match '[/\\]leyton$') { $title = "🍋 Leyton | $title" }
    if ($RepoRoot -match '[/\\]cf[/\\]'     -or $RepoRoot -match '[/\\]cf$')     { $title = "🐔 CF | $title" }

    if ($Label)    { $title = "$Label | $title" }
    if ($IsAdmin)  { $title = "👮‍♂️ | $title" }
    if ($PrNumber) { $title = "#$PrNumber | $title" }

    return $title
}
