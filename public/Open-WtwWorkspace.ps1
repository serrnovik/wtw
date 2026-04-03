function Open-WtwWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Name,

        [string] $Repo,
        [string] $Editor
    )

    $registry = Get-WtwRegistry
    $config = Get-WtwConfig

    $editorCmd = if ($Editor) { $Editor } elseif ($config.editor) { $config.editor } else { 'code' }

    # Find workspace file
    $wsFile = $null

    foreach ($repoName in $registry.repos.PSObject.Properties.Name) {
        $repoEntry = $registry.repos.$repoName
        if ($Repo -and -not (Test-WtwAliasMatch $repoEntry $Repo) -and $repoName -ne $Repo) { continue }

        # Main repo?
        if ((Test-WtwAliasMatch $repoEntry $Name) -or $repoName -eq $Name) {
            $wsFile = $repoEntry.templateWorkspace
            break
        }

        # Worktree?
        if ($repoEntry.worktrees -and $repoEntry.worktrees.PSObject.Properties.Name -contains $Name) {
            $wsFile = $repoEntry.worktrees.$Name.workspace
            break
        }

        # alias-task format
        if ($Name -match '^(.+?)-(.+)$') {
            $a = $Matches[1]; $t = $Matches[2]
            if (((Test-WtwAliasMatch $repoEntry $a) -or $repoName -eq $a) -and
                $repoEntry.worktrees -and $repoEntry.worktrees.PSObject.Properties.Name -contains $t) {
                $wsFile = $repoEntry.worktrees.$t.workspace
                break
            }
        }
    }

    if (-not $wsFile) {
        Write-Error "No workspace found for '$Name'. Run 'wtw list' to see available targets."
        return
    }

    if (-not (Test-Path $wsFile)) {
        Write-Error "Workspace file missing: $wsFile"
        return
    }

    Write-Host "  Opening in ${editorCmd}: $wsFile" -ForegroundColor Green
    & $editorCmd $wsFile
}
