function Register-WtwProfile {
    [CmdletBinding()]
    param()

    $registry = Get-WtwRegistry
    $repoNames = $registry.repos.PSObject.Properties.Name

    if (-not $repoNames -or $repoNames.Count -eq 0) {
        Write-Verbose 'wtw: No repos registered, skipping profile aliases.'
        return
    }

    foreach ($repoName in $repoNames) {
        $repo = $registry.repos.$repoName
        $alias = $repo.alias
        if (-not $alias) { continue }

        # Main repo alias: e.g., "sn3" -> go to snowmain main
        $mainPath = $repo.mainPath
        $sessionScript = $repo.sessionScript

        $goMainBlock = {
            param($p, $s)
            if (Get-Command 'Set-GitRepo' -ErrorAction SilentlyContinue) {
                $tool = if ($s) { $s } else { 'start-repository-session.ps1' }
                Set-GitRepo -gitRoot $p -toolName $tool
            } else {
                Set-Location $p
                $script = Join-Path $p ($s ?? 'start-repository-session.ps1')
                if (Test-Path $script) { & $script }
            }
        }.GetNewClosure()

        # Create function and alias for main repo
        $fnName = "WtwGo-$alias"
        Set-Item -Path "function:global:$fnName" -Value {
            $goMainBlock.Invoke($mainPath, $sessionScript)
        }.GetNewClosure()
        Set-Alias -Name $alias -Value $fnName -Scope Global -Force

        # Per-worktree aliases
        if ($repo.worktrees) {
            foreach ($taskName in $repo.worktrees.PSObject.Properties.Name) {
                $wt = $repo.worktrees.$taskName
                $wtPath = $wt.path
                $wtAlias = "$alias-$taskName"
                $wtFnName = "WtwGo-$wtAlias"

                Set-Item -Path "function:global:$wtFnName" -Value {
                    $goMainBlock.Invoke($wtPath, $sessionScript)
                }.GetNewClosure()
                Set-Alias -Name $wtAlias -Value $wtFnName -Scope Global -Force
            }
        }
    }

    Write-Verbose "wtw: Registered profile aliases for $($repoNames.Count) repo(s)."
}
