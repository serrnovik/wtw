function Show-WtwCommandHelp {
    param([string] $Command)

    $help = switch ($Command) {
        'init'        { @('wtw init [aliases...]', 'Register current repo with wtw.', '', 'Options:', '  --template <alias|path>     Share workspace settings from another repo or file', '  --startup-script <name>     Script to run on session entry (overrides auto-detect)', '  --startup-script-zsh <name> Zsh-specific session script (e.g. start-session.zsh)', '  --startup-script-bash <name> Bash-specific session script', '  --workspaces-dir <path>     Override workspace files directory', '  --name <key>                Override the registry key', '', 'Session scripts are detected by extension:', '  .ps1  -> run with pwsh       (default for PowerShell sessions)', '  .zsh  -> sourced in zsh      .sh/.bash -> sourced in bash/zsh') }
        'add'         { @('wtw add [path]', 'Add an existing repo or worktree to the registry.', '', 'Arguments:', '  path    Path to repo (default: current directory)') }
        'create'      { @('wtw create <task>', 'Create a new git worktree + workspace for a task/branch.', '', 'Arguments:', '  task    Branch/task name for the worktree') }
        'list'        { @('wtw list [repo]', 'List registered repos and their worktrees.', '', 'Arguments:', '  repo    Filter to a specific repo (optional)') }
        'ls'          { @('wtw list [repo]', 'List registered repos and their worktrees.', '', 'Arguments:', '  repo    Filter to a specific repo (optional)') }
        'go'          { @('wtw go <name>', 'Switch to a worktree (cd + session init).', '', 'Arguments:', '  name    Repo alias, task name, or alias-task combo') }
        'open'        { @('wtw open [name]', 'Open workspace in default editor.', '', 'Arguments:', '  name    Target to open (default: detected from cwd)', '', 'Falls back to opening the directory if no workspace file exists.') }
        'remove'      { @('wtw remove <task>', 'Remove a worktree and its workspace file.', '', 'Arguments:', '  task    Name of the worktree to remove') }
        'rm'          { @('wtw remove <task>', 'Remove a worktree and its workspace file.', '', 'Arguments:', '  task    Name of the worktree to remove') }
        'workspace'   { @('wtw workspace <name>', 'Generate a workspace file only (no git worktree).', '', 'Arguments:', '  name    Target repo/worktree') }
        'ws'          { @('wtw workspace <name>', 'Generate a workspace file only (no git worktree).', '', 'Arguments:', '  name    Target repo/worktree') }
        'copy'        { @('wtw copy <name>', 'Create a standalone copy of workspace from template.', '', 'Arguments:', '  name    Target repo/worktree') }
        'sync'        { @('wtw sync [name] [--all]', 'Re-apply template settings to managed workspaces.', '', 'Arguments:', '  name    Target workspace (alias, task, or file path; default: detected from cwd)', '', 'Options:', '  --all               Sync all managed workspaces', '  --repo <name>       Limit --all to a specific repo', '  --template <path>   Override template source', '  --dry-run           Show what would be synced without writing', '  --color-source      json | workspace (single-file sync; skips interactive prompt)', '                      Default when omitted: prompt if interactive, else json-first', '', 'Examples:', '  wtw sync                  Sync current workspace', '  wtw sync sn3-fix          Sync a specific workspace by name', '  wtw sync --all            Sync all registered workspaces', '  wtw sync --all --repo sn3 Sync all workspaces for one repo') }
        'color'       { @('wtw color [name] [hex|random]', 'Set or show the Peacock color for a workspace.', '', 'Arguments:', '  name     Target workspace (default: detected from cwd)', '  color    A hex color (rrggbb) or "random" for max contrast', '', 'Options:', '  --no-sync   Skip syncing the workspace file after color change', '', 'Examples:', '  wtw color                  Show color for current workspace', '  wtw color sn3 random       Pick a maximally contrasting color', '  wtw color fix-wtw e05d44   Set a specific color', '', 'Note: # starts a comment in PowerShell. Either omit it', '  or quote it: ''#e05d44''') }
        'clean'       { @('wtw clean', 'Remove stale AI-created worktrees that no longer have active branches.') }
        'install'     { @('wtw install', 'Install or update wtw globally to ~/.wtw/module/.', '', 'Options:', '  --skip-profile  Skip modifying shell profile') }
        'update'      { @('wtw install', 'Install or update wtw globally to ~/.wtw/module/.', '', 'Options:', '  --skip-profile  Skip modifying shell profile') }
        'skill'       { @('wtw skill [--agent claude|agents|all]', 'Install the wtw AI skill into the current repo.', '', 'Copies skill definitions so AI agents (Claude, Codex, Cursor, Gemini)', 'can discover and use wtw commands.', '', 'Options:', '  --agent claude    Claude Code only (.claude/skills/)', '  --agent agents    Cross-agent format (.agents/skills/)', '  --agent all       Both (default)') }
        default {
            # Check if it's an editor command
            $resolved = Resolve-WtwEditorCommand $Command
            if ($resolved) {
                @("wtw $Command [name]", "Open workspace/directory in $resolved.", '', 'Arguments:', '  name    Target to open (default: detected from cwd)', '', 'Falls back to opening the directory if no workspace file exists.')
            } else {
                $null
            }
        }
    }

    if ($help) {
        Write-Host ''
        Write-Host "  $($help[0])" -ForegroundColor Cyan
        for ($i = 1; $i -lt $help.Count; $i++) {
            Write-Host "  $($help[$i])"
        }
        Write-Host ''
    } else {
        Invoke-Wtw
    }
}
