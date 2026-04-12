# Tab completion for wtw CLI
Register-ArgumentCompleter -Native -CommandName wtw -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $tokens = $commandAst.ToString() -split '\s+'
    $tokenCount = $tokens.Count

    # Complete subcommands (position 1)
    if ($tokenCount -le 2) {
        $subcommands = @(
            @{ Name = 'init';   Tip = 'Register current repo in wtw' }
            @{ Name = 'create'; Tip = 'Create worktree + workspace' }
            @{ Name = 'list';   Tip = 'List registered worktrees' }
            @{ Name = 'go';     Tip = 'Switch to worktree' }
            @{ Name = 'open';   Tip = 'Open workspace in editor' }
            @{ Name = 'remove'; Tip = 'Remove worktree + workspace' }
            @{ Name = 'clean';  Tip = 'Clean stale AI worktrees' }
            @{ Name = 'skill';  Tip = 'Install AI skill into current repo' }
            @{ Name = 'help';   Tip = 'Show help' }
        )
        $subcommands | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Tip)
        }
        return
    }

    $subCommand = $tokens[1]

    # Complete targets for go/open/remove (position 2)
    if ($subCommand -in @('go', 'open', 'remove', 'rm') -and $tokenCount -le 3) {
        $registryPath = Join-Path $HOME '.wtw' 'registry.json'
        if (-not (Test-Path $registryPath)) { return }
        $registry = Get-Content $registryPath -Raw | ConvertFrom-Json

        $targets = @()
        foreach ($repoName in $registry.repos.PSObject.Properties.Name) {
            $repo = $registry.repos.$repoName
            $alias = $repo.alias
            if ($alias) {
                $targets += @{ Name = $alias; Tip = "$repoName (main)" }
            }
            if ($repo.worktrees) {
                foreach ($task in $repo.worktrees.PSObject.Properties.Name) {
                    $targets += @{ Name = "$alias-$task"; Tip = "$repoName worktree: $task" }
                    $targets += @{ Name = $task; Tip = "$repoName worktree: $task" }
                }
            }
        }

        $targets | Where-Object { $_.Name -like "$wordToComplete*" } | Sort-Object -Property Name -Unique | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Tip)
        }
        return
    }

    # Complete flags
    if ($wordToComplete -like '-*' -or $wordToComplete -like '--*') {
        $flags = switch ($subCommand) {
            'init'   { @('--template', '--startup-script', '--workspaces-dir', '--name') }
            'skill'  { @('--agent') }
            'create' { @('--branch', '--repo', '--open', '--no-branch') }
            'clean'  { @('--dry-run', '--force') }
            'remove' { @('--repo', '--force') }
            'open'   { @('--repo', '--editor') }
            'list'   { @('--repo', '--detailed', '-d') }
            default  { @() }
        }
        $flags | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_)
        }
    }
}
