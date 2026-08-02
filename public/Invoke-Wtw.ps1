

function Invoke-Wtw {
    <#
    .SYNOPSIS
        Main CLI dispatcher for wtw.
    .DESCRIPTION
        Routes subcommands (create, list, sync, clean, etc.) to their handler
        functions. Parses raw CLI arguments via Convert-WtwArgsToSplat and splats
        them to the target command. Does not use [CmdletBinding()] because it
        relies on automatic $args for flexible dispatch.
    .EXAMPLE
        wtw create auth --open
        Creates a worktree and workspace for "auth" and opens it in the editor.
    .EXAMPLE
        wtw sync --all --dry-run
        Preview-syncs all managed workspaces.
    #>
    $Command = $null
    $rawArgs = @()

    if ($args.Count -gt 0) {
        $Command = $args[0]
    }
    if ($args.Count -gt 1) {
        $rawArgs = $args[1..($args.Count - 1)]
    }

    # Newer-version hint. Emitted up front because the dispatch below returns
    # from many branches. Cache-only, silent on failure, and skipped for the
    # internal `__*` commands whose stdout the shell wrappers parse.
    if ([string]$Command -notlike '__*') {
        Write-WtwUpdateNotice
    }

    if (-not $Command) {
        Write-Host ''
        Write-Host '  wtw - Git Worktree + Workspace Manager' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  Commands:' -ForegroundColor Yellow
        Write-Host '    init [aliases]    Initialise current repo as a main repo in the registry (run once, from inside it)'
        Write-Host '    add [path]        Adopt an existing on-disk worktree with full registration (workspace + color + cmux/SourceGit/etc.)'
        Write-Host '    create <task>     Create worktree + branch (pass --branch <existing-ref> or --adopt to attach to an existing branch)'
        Write-Host '    list [repo] [-d|--detailed] [--wide]  List repos/worktrees'
        Write-Host '    info <name>       Show full details for a repo or worktree  (alias: show)'
        Write-Host '    go <name>         Switch to worktree (cd + session init)'
        Write-Host '    open [name]       Open workspace in editor (default: current)'
        Write-Host '    cursor [name]     Open in Cursor      (alias: cur)'
        Write-Host '    code [name]       Open in VS Code     (alias: co)'
        Write-Host '    antigravity [name] Open in Antigravity (alias: anti)'
        Write-Host '    windsurf [name]   Open in Windsurf    (alias: wind, ws)'
        Write-Host '    codium [name]     Open in VSCodium    (alias: vscodium)'
        Write-Host '    chatgpt [name] [--skip-restart]  Open in ChatGPT (aliases: cgpt, codex)'
        Write-Host '    cmux [name]       Open in cmux terminal workspace (alias: cm)'
        Write-Host '    wmux [name]       Open in wmux terminal workspace (alias: wm)'
        Write-Host '    claude [name]     Open Claude.ai app  (alias: cowork)'
        Write-Host '    claudecode [name] [--prompt <text>]  New Claude Code chat in the worktree (alias: ccode)'
        Write-Host '    t3 [name]         Open T3 Code Alpha  (alias: t3code)'
        Write-Host '    ss [name]         Find & open matching Superset workspace (alias: superset, supersetsh)'
        Write-Host '    remove <task>     Remove worktree + workspace  (alias: rm, delete, del)'
        Write-Host '    unregister <name> Drop repo or worktree from wtw registry only (alias: unreg)'
        Write-Host '    workspace <name>  Generate workspace file only (no git worktree)'
        Write-Host '    copy <name>       Standalone copy of workspace from template'
        Write-Host '    color [name] [hex|random]   Set workspace color (--no-sync to skip sync)'
        Write-Host '    sync [file|--all] Re-apply template to managed workspaces'
        Write-Host '    clean             Clean stale AI worktrees'
        Write-Host '    agent profile ... Configure agentctl profile overlays'
        Write-Host '    install           Install/update wtw globally (~/.wtw/module/)'
        Write-Host '    skill [--agent X] Install AI skill into current repo (claude/agents/all)'
        Write-Host '    sbx [task] [--name <n>] [--agent <a>] [--writable] [--dry-run]'
        Write-Host '                      Launch AI sandbox (sbx) with workspace folders mounted'
        Write-Host ''
        Write-Host '  Options:' -ForegroundColor Yellow
        Write-Host '    --help, -h        Show this help'
        Write-Host ''
        return
    }

    $parsed = Convert-WtwArgsToSplat $rawArgs
    $splat = $parsed.Splat
    $pos = $parsed.Positional

    # --help / -h / help on any subcommand → show command-specific help
    if ($splat.Contains('Help') -or $splat.Contains('h') -or $pos -contains 'help') {
        Show-WtwCommandHelp $Command
        return
    }

    # Merge positional args into splat at position keys for commands that take them
    # Most commands take a single positional arg (task/name)
    # We handle this by manually adding positional params
    switch ($Command) {
        'init'    { if ($pos.Count -gt 0) { $splat['Alias'] = $pos[0] }; Initialize-WtwConfig @splat }
        'add'     {
            if ($pos.Count -gt 0) { $splat['Path'] = $pos[0] }
            # Match `wtw create --name <pretty>` ergonomics — splat-key 'Name'
            # → PrettyName param so the same user-facing flag works here.
            if ($splat.Contains('Name')) {
                $splat['PrettyName'] = $splat['Name']
                $splat.Remove('Name')
            }
            Add-WtwEntry @splat
        }
        'create'  {
            if ($pos.Count -gt 0) {
                $splat['Task'] = if ($pos.Count -eq 1) { $pos[0] } else { $pos -join ' ' }
            }
            # --name <pretty> → PrettyName param (avoids clash with positional Name resolution).
            # `$splat` is an ordered dictionary (`[ordered] @{ ... }`), which exposes
            # `Contains()` rather than `ContainsKey()` — calling the latter would throw
            # at runtime the moment `wtw create --name <pretty>` is invoked.
            if ($splat.Contains('Name')) {
                $splat['PrettyName'] = $splat['Name']
                $splat.Remove('Name')
            }
            New-WtwWorktree @splat
        }
        'list'    { if ($pos.Count -gt 0) { $splat['Repo'] = $pos[0] }; Get-WtwList @splat }
        'ls'      { if ($pos.Count -gt 0) { $splat['Repo'] = $pos[0] }; Get-WtwList @splat }
        'info'    { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Show-WtwInfo @splat }
        'show'    { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Show-WtwInfo @splat }
        'go'      { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Enter-WtwWorktree @splat }
        'open'    { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Open-WtwWorkspace @splat }
        'remove'  { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Remove-WtwWorktree @splat }
        'rm'      { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Remove-WtwWorktree @splat }
        'delete'  { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Remove-WtwWorktree @splat }
        'del'     { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Remove-WtwWorktree @splat }
        'unregister' { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Unregister-WtwEntry @splat }
        'unreg'   { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Unregister-WtwEntry @splat }
        'workspace' { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; New-WtwWorkspace @splat }
        'ws'        { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; New-WtwWorkspace @splat }
        'copy'      { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Copy-WtwWorkspace @splat }
        'sync'      { if ($pos.Count -gt 0) { $splat['Target'] = $pos[0] }; Sync-WtwWorkspace @splat }
        'color'     { 
            $resolved = Resolve-WtwColorArgs $pos
            foreach ($k in $resolved.Keys) { $splat[$k] = $resolved[$k] }
            Set-WtwColor @splat 
        }
        'clean'     { Invoke-WtwClean @splat }
        'agent'     { Invoke-WtwAgent @rawArgs }
        'install'   { Install-Wtw @splat }
        'update'    { Install-Wtw @splat }
        'skill'     { Install-WtwSkill @splat }
        'sbx'       {
            if ($pos.Count -gt 0) { $splat['Instruction'] = $pos -join ' ' }
            Invoke-WtwSbx @splat
        }
        'help'    { Invoke-Wtw }
        # Internal commands for shell integration (zsh/bash wrappers call these)
        '__resolve_path' {
            # Output: just the absolute path to the target (single line, no
            # tabs). Used by wtw.cmd so cmd.exe can `cd /d` to it cleanly
            # without parsing tab-delimited fields.
            if ($pos.Count -eq 0) { Write-Error "Usage: wtw __resolve_path <name>"; return }
            $target = & { Resolve-WtwTarget $pos[0] } 6>$null
            if (-not $target) { exit 1 }
            $p = if ($target.WorktreeEntry) { $target.WorktreeEntry.path } else { $target.RepoEntry.mainPath }
            Write-Output $p
        }
        '__resolve' {
            # Output: path\tcolor\ttitle\tstartup_script\tworktree_id\tworktree_index
            # Used by wtw.zsh/wtw.bash — must be clean stdout (no Write-Host noise)
            # Optional: --shell zsh|bash to resolve per-shell session script
            if ($pos.Count -eq 0) { Write-Error "Usage: wtw __resolve <name> [--shell zsh|bash]"; return }
            $shellType = $splat['Shell'] ?? ''
            $target = & { Resolve-WtwTarget $pos[0] } 6>$null
            if (-not $target) { exit 1 }
            $p = if ($target.WorktreeEntry) { $target.WorktreeEntry.path } else { $target.RepoEntry.mainPath }
            $c = if ($target.WorktreeEntry) {
                $target.WorktreeEntry.color
            } else {
                Get-WtwPropertyValue -Object (Get-WtwColors).assignments -Name "$($target.RepoName)/main"
            }
            $t = if ($target.TaskName) { "$($target.RepoName)/$($target.TaskName)" } else { $target.RepoName }
            $s = Resolve-WtwSessionScript -RepoEntry $target.RepoEntry -Shell $shellType
            # Compute worktree index for env vars
            $wtId = $target.TaskName ?? ''
            $wtIndex = 0
            if ($target.TaskName -and $target.RepoEntry.worktrees) {
                $i = 1
                foreach ($tn in (Get-WtwPropertyNames -Object $target.RepoEntry.worktrees)) {
                    if ($tn -eq $target.TaskName) { $wtIndex = $i; break }
                    $i++
                }
            }
            Write-Output "${p}`t${c}`t${t}`t${s}`t${wtId}`t${wtIndex}"
        }
        '__aliases' {
            # Output: alias_name\tpath\tcolor\ttitle\tstartup_script\tworktree_id\tworktree_index
            # Optional: --shell zsh|bash to resolve per-shell session scripts
            $shellType = $splat['Shell'] ?? ''
            $registry = Get-WtwRegistry
            $colors = Get-WtwColors
            foreach ($repoName in (Get-WtwPropertyNames -Object $registry.repos)) {
                $repo = $registry.repos.$repoName
                $aliases = Get-WtwRepoAliases $repo
                $ss = Resolve-WtwSessionScript -RepoEntry $repo -Shell $shellType
                $mainColor = Get-WtwPropertyValue -Object $colors.assignments -Name "$repoName/main" -DefaultValue ''
                foreach ($a in $aliases) {
                    Write-Output "${a}`t$($repo.mainPath)`t${mainColor}`t${repoName}`t${ss}`t`t0"
                }
                if ($repo.worktrees) {
                    $wtIdx = 1
                    foreach ($taskName in (Get-WtwPropertyNames -Object $repo.worktrees)) {
                        $wt = $repo.worktrees.$taskName
                        $wtColor = Get-WtwPropertyValue -Object $wt -Name 'color' -DefaultValue ''
                        $wtTitle = "$repoName/$taskName"
                        foreach ($a in $aliases) {
                            Write-Output "${a}-${taskName}`t$($wt.path)`t${wtColor}`t${wtTitle}`t${ss}`t${taskName}`t${wtIdx}"
                        }
                        $wtIdx++
                    }
                }
            }
        }
        '__cmux_apply_current' {
            # Called silently by shell integration when a terminal starts inside
            # cmux. Socket commands are allowed from inside cmux, unlike the
            # external app-open fallback path.
            Initialize-WtwCmuxCurrentSession
        }
        '__cmux_init_current' {
            # PowerShell cmux startup path. Applies the normal wtw terminal title,
            # env vars, and session script for the cwd target, then refreshes cmux
            # workspace metadata.
            Initialize-WtwCmuxCurrentSession -ApplyTerminalSession
        }
        default   {
            # Check if command is an editor shortcut (cursor, cur, code, co, anti, etc.)
            $resolvedEditor = Resolve-WtwEditorCommand $Command
            if ($resolvedEditor) {
                $splat['Editor'] = $resolvedEditor
                if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }
                Open-WtwWorkspace @splat
            } else {
                # Fallback: treat unknown command as "go <name>"
                Write-Host "  → " -ForegroundColor DarkGray -NoNewline
                Write-Host "wtw $Command" -ForegroundColor White -NoNewline
                Write-Host "  interpreted as  " -ForegroundColor DarkGray -NoNewline
                Write-Host "wtw go $Command" -ForegroundColor Cyan
                Enter-WtwWorktree -Name $Command @splat
            }
        }
    }
}
