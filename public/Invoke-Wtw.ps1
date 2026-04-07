function Convert-WtwArgsToSplat {
    param([object[]] $ArgList)

    $splat = [ordered]@{}
    $positional = @()
    $i = 0

    while ($i -lt $ArgList.Count) {
        $arg = "$($ArgList[$i])"

        # Translate --kebab-case to PascalCase
        if ($arg -match '^--([a-z][a-z0-9-]*)$') {
            $parts = $Matches[1] -split '-'
            $arg = '-' + (($parts | ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1) }) -join '')
        }

        if ($arg -match '^-(\w+)$') {
            $paramName = $Matches[1]
            # Peek at next arg to decide switch vs value
            if (($i + 1) -lt $ArgList.Count -and "$($ArgList[$i + 1])" -notmatch '^-') {
                $splat[$paramName] = $ArgList[$i + 1]
                $i += 2
            } else {
                $splat[$paramName] = [switch]::Present
                $i++
            }
        } else {
            $positional += $arg
            $i++
        }
    }

    # Add positional args as numbered keys won't work — return them separately
    return @{ Splat = $splat; Positional = $positional }
}

function Invoke-Wtw {
    $Command = $null
    $rawArgs = @()

    if ($args.Count -gt 0) {
        $Command = $args[0]
    }
    if ($args.Count -gt 1) {
        $rawArgs = $args[1..($args.Count - 1)]
    }

    if (-not $Command) {
        Write-Host ''
        Write-Host '  wtw - Git Worktree + Workspace Manager' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  Commands:' -ForegroundColor Yellow
        Write-Host '    init [aliases]    Register current repo (--template <alias> to share settings)'
        Write-Host '    add [path]        Add existing repo/worktree to registry'
        Write-Host '    create <task>     Create worktree + workspace'
        Write-Host '    list              List registered worktrees'
        Write-Host '    go <name>         Switch to worktree (cd + session init)'
        Write-Host '    open [name]       Open workspace in editor (default: current)'
        Write-Host '    cursor [name]     Open in Cursor   (alias: cur)'
        Write-Host '    code [name]       Open in VS Code  (alias: co)'
        Write-Host '    antigravity [name] Open in Antigravity (alias: anti)'
        Write-Host '    remove <task>     Remove worktree + workspace'
        Write-Host '    workspace <name>  Generate workspace file only (no git worktree)'
        Write-Host '    copy <name>       Standalone copy of workspace from template'
        Write-Host '    color [name] [#hex|random]  Set workspace color (--no-sync to skip sync)'
        Write-Host '    sync [file|--all] Re-apply template to managed workspaces'
        Write-Host '    clean             Clean stale AI worktrees'
        Write-Host '    install           Install/update wtw globally (~/.wtw/module/)'
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
        'add'     { if ($pos.Count -gt 0) { $splat['Path'] = $pos[0] }; Add-WtwEntry @splat }
        'create'  { if ($pos.Count -gt 0) { $splat['Task'] = $pos[0] }; New-WtwWorktree @splat }
        'list'    { if ($pos.Count -gt 0) { $splat['Repo'] = $pos[0] }; Get-WtwList @splat }
        'ls'      { if ($pos.Count -gt 0) { $splat['Repo'] = $pos[0] }; Get-WtwList @splat }
        'go'      { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Enter-WtwWorktree @splat }
        'open'    { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Open-WtwWorkspace @splat }
        'remove'  { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Remove-WtwWorktree @splat }
        'rm'      { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Remove-WtwWorktree @splat }
        'workspace' { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; New-WtwWorkspace @splat }
        'ws'        { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; New-WtwWorkspace @splat }
        'copy'      { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; Copy-WtwWorkspace @splat }
        'sync'      { if ($pos.Count -gt 0) { $splat['Target'] = $pos[0] }; Sync-WtwWorkspace @splat }
        'color'     { if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }; if ($pos.Count -gt 1) { $splat['Color'] = $pos[1] }; Set-WtwColor @splat }
        'clean'     { Invoke-WtwClean @splat }
        'install'   { Install-Wtw @splat }
        'update'    { Install-Wtw @splat }
        'help'    { Invoke-Wtw }
        default   {
            # Check if command is an editor shortcut (cursor, cur, code, co, anti, etc.)
            $resolvedEditor = Resolve-WtwEditorCommand $Command
            if ($resolvedEditor) {
                $splat['Editor'] = $resolvedEditor
                if ($pos.Count -gt 0) { $splat['Name'] = $pos[0] }
                Open-WtwWorkspace @splat
            } else {
                # Fallback: treat unknown command as "go <name>"
                Enter-WtwWorktree -Name $Command
            }
        }
    }
}
