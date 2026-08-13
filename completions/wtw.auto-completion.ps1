# Tab completion for wtw CLI
Register-ArgumentCompleter -Native -CommandName wtw -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    function Get-WtwRepoAliasesJson {
        param([psobject] $Repo)
        if ((Get-WtwPropertyNames -Object $Repo) -contains 'aliases' -and $Repo.aliases) {
            return @($Repo.aliases)
        }
        if ((Get-WtwPropertyNames -Object $Repo) -contains 'alias' -and $Repo.alias) {
            return @($Repo.alias)
        }
        return @()
    }

    function Get-WtwWorktreePath {
        param([psobject] $WorktreeEntry, [string] $TaskFallback)
        if ($WorktreeEntry -and (Get-WtwPropertyNames -Object $WorktreeEntry) -contains 'path' -and $WorktreeEntry.path) {
            return [string]$WorktreeEntry.path
        }
        return $TaskFallback
    }

    function Build-WtwAllTargets {
        param([psobject] $Registry)
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($repoName in (Get-WtwPropertyNames -Object $Registry.repos)) {
            $repo = $Registry.repos.$repoName
            $aliases = @(Get-WtwRepoAliasesJson $repo)
            $mainTip = if ($repo.mainPath) { "$repoName → $([string]$repo.mainPath)" } else { "$repoName (main)" }
            $list.Add([ordered]@{ Name = $repoName; Tip = $mainTip })
            foreach ($a in $aliases) {
                if ($a) { $list.Add([ordered]@{ Name = [string]$a; Tip = $mainTip }) }
            }
            if ($repo.worktrees) {
                foreach ($task in (Get-WtwPropertyNames -Object $repo.worktrees)) {
                    $wt = $repo.worktrees.$task
                    $pathTip = Get-WtwWorktreePath -WorktreeEntry $wt -TaskFallback $task
                    $wtTip = "$repoName → $pathTip"
                    $list.Add([ordered]@{ Name = $task; Tip = $wtTip })
                    foreach ($a in $aliases) {
                        if ($a) {
                            $list.Add([ordered]@{ Name = "$a-$task"; Tip = $wtTip })
                        }
                    }
                }
            }
        }
        $seen = @{}
        foreach ($item in $list) {
            if (-not $seen.ContainsKey($item.Name)) {
                $seen[$item.Name] = $true
                $item
            }
        }
    }

    function Build-WtwRepoFilterList {
        param([psobject] $Registry)
        $byName = @{}
        foreach ($repoName in (Get-WtwPropertyNames -Object $Registry.repos)) {
            $repo = $Registry.repos.$repoName
            if (-not $byName.ContainsKey($repoName)) {
                $byName[$repoName] = @{ Name = $repoName; Tip = "repo $repoName" }
            }
            foreach ($a in (Get-WtwRepoAliasesJson $repo)) {
                if ($a -and -not $byName.ContainsKey([string]$a)) {
                    $byName[[string]$a] = @{ Name = [string]$a; Tip = "alias → $repoName" }
                }
            }
        }
        return @($byName.Values)
    }

    function Filter-WtwMatches {
        param(
            [object[]] $Items,
            [string] $Word
        )
        if ([string]::IsNullOrWhiteSpace($Word)) {
            return $Items | Sort-Object -Property Name
        }
        $esc = [WildcardPattern]::Escape($Word)
        $hit = $Items | Where-Object { $_.Name -like "$esc*" -or $_.Name -like "*$esc*" }
        $prefix = @($hit | Where-Object { $_.Name -like "$esc*" } | Sort-Object -Property Name)
        $rest = @($hit | Where-Object { $_.Name -notlike "$esc*" } | Sort-Object -Property Name)
        return @($prefix + $rest)
    }

    $elems = @($commandAst.CommandElements)
    $registryPath = Join-Path $HOME '.wtw' 'registry.json'

    $knownSubcommands = @(
        'init', 'add', 'create', 'list', 'ls', 'go', 'open', 'remove', 'rm', 'unregister', 'unreg',
        'workspace', 'ws', 'copy', 'sync', 'color', 'clean', 'agent', 'install', 'update', 'skill', 'help',
        '__resolve', '__aliases',
        'cursor', 'cur', 'code', 'co', 'antigravity', 'anti', 'ag', 'windsurf', 'wind',
        'codium', 'vscodium', 'sourcegit', 'sgit', 'sg',
        'codex', 'droid', 'factory', 'claude', 'cowork', 'claudecode', 'ccode', 't3', 't3code',
        'ss', 'superset', 'supersetsh'
    )

    $targetSubcommands = @(
        'go', 'open', 'remove', 'rm', 'unregister', 'unreg', 'sync', 'color',
        'cursor', 'cur', 'code', 'co', 'antigravity', 'anti', 'ag', 'windsurf', 'wind',
        'codium', 'vscodium', 'sourcegit', 'sgit', 'sg',
        'codex', 'droid', 'factory', 'claude', 'cowork', 'claudecode', 'ccode', 't3', 't3code',
        'ss', 'superset', 'supersetsh',
        'workspace', 'ws'
    )

    # First token after wtw: subcommand (or refine partial)
    if ($elems.Count -lt 2) {
        $subcommands = @(
            @{ Name = 'init';   Tip = 'Register current repo in wtw' }
            @{ Name = 'add';    Tip = 'Add existing repo/worktree to registry' }
            @{ Name = 'create'; Tip = 'Create worktree + workspace' }
            @{ Name = 'list';   Tip = 'List registered worktrees' }
            @{ Name = 'go';     Tip = 'Switch to worktree' }
            @{ Name = 'open';   Tip = 'Open workspace in editor' }
            @{ Name = 'remove'; Tip = 'Remove worktree + workspace' }
            @{ Name = 'unregister'; Tip = 'Drop repo/worktree from wtw registry only' }
            @{ Name = 'unreg'; Tip = 'Alias for unregister' }
            @{ Name = 'clean';       Tip = 'Clean stale AI worktrees' }
            @{ Name = 'agent';       Tip = 'Configure agentctl profile overlays' }
            @{ Name = 'skill';       Tip = 'Install AI skill into current repo' }
            @{ Name = 'chatgpt';     Tip = 'Open in ChatGPT (aliases: cgpt, codex)' }
            @{ Name = 'cgpt';        Tip = 'Open in ChatGPT' }
            @{ Name = 'codex';       Tip = 'Open in ChatGPT' }
            @{ Name = 'droid';       Tip = 'Open in Factory desktop app (alias: factory)' }
            @{ Name = 'factory';     Tip = 'Open in Factory desktop app' }
            @{ Name = 'claude';      Tip = 'Open Claude.ai app' }
            @{ Name = 'claudecode';  Tip = 'New Claude Code chat in the worktree (alias: ccode)' }
            @{ Name = 't3';          Tip = 'Register + open a T3 Code project' }
            @{ Name = 'ss';          Tip = 'Find & open matching Superset workspace' }
            @{ Name = 'help';        Tip = 'Show help' }
        )
        $prefix = $wordToComplete
        $subcommands | Where-Object { $_.Name -like "$prefix*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Tip)
        }
        return
    }

    $firstArg = $elems[1].Extent.Text
    if ($firstArg -notin $knownSubcommands) {
        $subMatches = @($knownSubcommands | Where-Object { $_ -like "$firstArg*" } | Select-Object -Unique)
        if ($subMatches.Count -gt 0) {
            $subMatches | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "wtw $_")
            }
            return
        }
        if (-not (Test-Path $registryPath)) { return }
        $registry = Get-Content $registryPath -Raw | ConvertFrom-Json
        $targets = @(Build-WtwAllTargets $registry)
        $needle = if (-not [string]::IsNullOrWhiteSpace($wordToComplete)) { $wordToComplete } else { $firstArg }
        Filter-WtwMatches $targets $needle | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Tip)
        }
        return
    }

    $subCommand = $firstArg

    if (-not (Test-Path $registryPath)) { return }
    $registry = Get-Content $registryPath -Raw | ConvertFrom-Json

    # --repo value (previous token is --repo)
    if ($elems.Count -ge 3 -and $wordToComplete -notmatch '^-') {
        $prev = $elems[$elems.Count - 2].Extent.Text
        if ($prev -ieq '--repo' -and $subCommand -in @(
                'create', 'remove', 'rm', 'open', 'unregister', 'unreg', 'sync', 'list', 'ls'
            )) {
            $repos = Build-WtwRepoFilterList $registry
            Filter-WtwMatches $repos $wordToComplete | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Tip)
            }
            return
        }
    }

    # wtw list [repoFilter]
    if ($subCommand -in @('list', 'ls')) {
        if ($elems.Count -ge 3 -and $elems[2].Extent.Text -notlike '-*') {
            $repos = Build-WtwRepoFilterList $registry
            Filter-WtwMatches $repos $wordToComplete | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Tip)
            }
            return
        }
        if ($elems.Count -eq 2 -and [string]::IsNullOrWhiteSpace($wordToComplete)) {
            $repos = Build-WtwRepoFilterList $registry
            Filter-WtwMatches $repos '' | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Tip)
            }
            return
        }
    }

    # Positional target
    if ($subCommand -in $targetSubcommands) {
        if ($elems.Count -ge 3 -and $elems[2].Extent.Text -notlike '-*') {
            $targets = @(Build-WtwAllTargets $registry)
            Filter-WtwMatches $targets $wordToComplete | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Tip)
            }
            return
        }
        if ($elems.Count -eq 2 -and [string]::IsNullOrWhiteSpace($wordToComplete)) {
            $targets = @(Build-WtwAllTargets $registry)
            Filter-WtwMatches $targets '' | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Tip)
            }
            return
        }
    }

    if ($wordToComplete -like '-*' -or $wordToComplete -like '--*') {
        $flags = switch ($subCommand) {
            'init'   { @('--template', '--startup-script', '--startup-script-zsh', '--startup-script-bash', '--workspaces-dir', '--name') }
            'skill'  { @('--agent') }
            'add'    { @('--repo', '--task', '--branch') }
            'create' { @('--name', '--folder', '--branch', '--color', '--repo', '--open', '--no-branch', '--from', '--gt-track') }
            'clean'  { @('--dry-run', '--force') }
            'remove' { @('--repo', '--force') }
            'rm'     { @('--repo', '--force') }
            'unregister' { @('--repo', '--force') }
            'unreg'      { @('--repo', '--force') }
            'open'   { @('--repo', '--editor') }
            'list'   { @('--repo', '--detailed', '-d') }
            'ls'     { @('--repo', '--detailed', '-d') }
            'sync'   { @('--all', '--repo', '--template', '--dry-run', '--color-source') }
            'color'  { @('--no-sync') }
            default  { @() }
        }
        $flags | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_)
        }
    }
}
