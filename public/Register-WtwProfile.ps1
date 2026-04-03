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
        $aliases = Get-WtwRepoAliases $repo
        if (-not $aliases -or $aliases.Count -eq 0) { continue }

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

        # Create function + aliases for main repo (one function, multiple aliases)
        $primaryAlias = $aliases[0]
        $fnName = "WtwGo-$primaryAlias"
        Set-Item -Path "function:global:$fnName" -Value {
            $goMainBlock.Invoke($mainPath, $sessionScript)
        }.GetNewClosure()

        foreach ($a in $aliases) {
            Set-Alias -Name $a -Value $fnName -Scope Global -Force
        }

        # Per-worktree aliases: create for each repo alias
        if ($repo.worktrees) {
            foreach ($taskName in $repo.worktrees.PSObject.Properties.Name) {
                $wt = $repo.worktrees.$taskName
                $wtPath = $wt.path
                $wtFnName = "WtwGo-$primaryAlias-$taskName"

                Set-Item -Path "function:global:$wtFnName" -Value {
                    $goMainBlock.Invoke($wtPath, $sessionScript)
                }.GetNewClosure()

                foreach ($a in $aliases) {
                    Set-Alias -Name "$a-$taskName" -Value $wtFnName -Scope Global -Force
                }
            }
        }
    }

    Write-Verbose "wtw: Registered profile aliases for $($repoNames.Count) repo(s)."
}
