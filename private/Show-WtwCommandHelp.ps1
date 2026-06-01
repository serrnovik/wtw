function Show-WtwCommandHelp {
    param([string] $Command)

    $help = switch ($Command) {
        'init'        { @(
            'wtw init [aliases...]',
            'Initialise the *current repo* as a main repo in the wtw registry.',
            'Run this once, from inside the repo. Creates config + workspace template,',
            'picks a color for the main checkout, and registers aliases for `wtw go`.',
            'Use `wtw add` instead when the directory is an existing worktree.',
            '',
            'Options:',
            '  --template <alias|path>     Share workspace settings from another repo or file',
            '  --startup-script <name>     Script to run on session entry (overrides auto-detect)',
            '  --startup-script-zsh <name> Zsh-specific session script (e.g. start-session.zsh)',
            '  --startup-script-bash <name> Bash-specific session script',
            '  --workspaces-dir <path>     Override workspace files directory',
            '  --name <key>                Override the registry key',
            '',
            'Session scripts are detected by extension:',
            '  .ps1  -> run with pwsh       (default for PowerShell sessions)',
            '  .zsh  -> sourced in zsh      .sh/.bash -> sourced in bash/zsh'
        ) }
        'add'         { @(
            'wtw add [path]',
            'Adopt an *existing-on-disk* git worktree with full wtw registration.',
            'For worktrees created by `git worktree add` outside wtw. Runs the same',
            'post-setup as `wtw create`: workspace file from template, color, pretty',
            'name + color circle, and cmux / Codex / Superset / SourceGit / agentctl',
            'registration. Does NOT create branches or touch the worktree directory.',
            'For the parent repo itself use `wtw init`.',
            '',
            'Arguments:',
            '  path    Path to the worktree directory (default: current directory)',
            '',
            'Options:',
            '  --repo <name>     Parent repo alias (auto-detected from the worktree .git pointer)',
            '  --task <name>     Registry key (default: folder name with the `<repo>_` prefix stripped)',
            '  --branch <name>   Override the branch name (default: auto-detected via git)',
            '  --name <pretty>   Display name (Superset workspace title, cmux entry, etc.)',
            '  --color <hex|name|random>',
            '                    Workspace color. Same input as `create --color`.',
            '',
            'Examples:',
            '  wtw add ../snowmain1_foo --task foo',
            '  cd ../snowmain1_foo ; wtw add --task foo --color "forest green"'
        ) }
        'create'      { @(
            'wtw create <task> [options]',
            'Create a worktree + workspace for a task. Default: new branch named <task>.',
            'Pass --branch <existing-ref> to adopt that branch instead — adoption is',
            'inferred automatically when the ref already exists (local or remote-tracking).',
            'All the usual logic (color, workspace file, registry, cmux/Superset/SourceGit)',
            'runs in both cases.',
            '',
            'Arguments:',
            '  task    Branch/task name for the worktree (used as registry key)',
            '',
            'Options:',
            '  --name <pretty>     Display name (shown in `list -d`; Superset workspace title)',
            '  --folder <name>     Folder suffix (default: <task>). e.g. --folder p2 → repo_p2',
            '  --branch <name>     Branch to use:',
            '                       - if the ref already exists (local or `origin/<name>`),',
            '                         the worktree adopts it (auto)',
            '                       - otherwise a new branch with that name is created',
            '                         starting from HEAD (or --from if given)',
            '  --adopt             Force-adopt the existing branch named <task> (no --branch needed).',
            '                      Alias: --no-branch (legacy).',
            '  --from <ref>        Start point for a *new* branch (branch/tag/SHA, or `current`',
            '                      = cwd worktree''s branch). Ignored when adopting.',
            '  --gt-track          After creating, run `gt track` to register with Graphite.',
            '  --color <hex|name|random>',
            '                      Workspace color. Hex (#rrggbb / rrggbb), palette name (e.g.',
            '                      "forest green", "navy"), or "random" (default).',
            '  --repo <alias>      Target repo when not auto-detected from cwd',
            '  --open              Open the workspace in the default editor after creating',
            '',
            'Examples:',
            '  wtw create auth                                   # new branch + new worktree',
            '  wtw create my-feature --branch my-feature         # adopt existing local (auto)',
            '  wtw create my-feature --branch origin/my-feature  # adopt remote (creates tracking)',
            '  wtw create my-feature --adopt                     # same as --branch my-feature',
            '  wtw create p2 --folder p2 --branch some-long-existing-branch',
            '  wtw create initiative-016 --from MS-phase-5-swim-polish   # stack on another branch',
            '  wtw create auth --color "forest green"'
        ) }
        'list'        { @('wtw list [repo]', 'List registered repos and their worktrees.', '', 'Arguments:', '  repo    Filter to a specific repo (optional)', '', 'Options:', '  -d, --detailed   Card layout with file links', '  --wide           Full aliases, paths, and branch names (no truncation)') }
        'ls'          { @('wtw list [repo]', 'List registered repos and their worktrees.', '', 'Arguments:', '  repo    Filter to a specific repo (optional)', '', 'Options:', '  -d, --detailed   Card layout with file links', '  --wide           Full aliases, paths, and branch names (no truncation)') }
        'info'        { @('wtw info <name>', 'Show full details for a repo or all its worktrees.', '', 'Arguments:', '  name    Anything wtw go accepts: repo alias, task name, alias-task combo, prefix, or fuzzy', '', 'Alias: wtw show') }
        'show'        { @('wtw info <name>', 'Show full details for a repo or all its worktrees.', '', 'Arguments:', '  name    Anything wtw go accepts: repo alias, task name, alias-task combo, prefix, or fuzzy', '', 'Alias: wtw show') }
        'go'          { @('wtw go <name>', 'Switch to a worktree (cd + session init).', '', 'Arguments:', '  name    Repo alias, task name, or alias-task combo') }
        'open'        { @('wtw open [name]', 'Open workspace in default editor.', '', 'Arguments:', '  name    Target to open (default: detected from cwd)', '', 'Falls back to opening the directory if no workspace file exists.') }
        'remove'      { @('wtw remove <task>', 'Remove a worktree and its workspace file.', '', 'Arguments:', '  task    Name of the worktree to remove') }
        'rm'          { @('wtw remove <task>', 'Remove a worktree and its workspace file.', '', 'Arguments:', '  task    Name of the worktree to remove') }
        'unregister'  { @('wtw unregister <name>', 'Remove a repo or worktree from the wtw registry only (no git/disk changes).', 'Pairs with: wtw init (main repo), wtw add (worktree listing). For full worktree teardown use wtw remove.', '', 'Arguments:', '  name    Repo alias, path, worktree, or alias-task', '', 'Options:', '  --repo <name>   Disambiguate when the same task exists in multiple repos', '  --force         Skip confirmation') }
        'unreg'       { @('wtw unregister <name>', 'Remove a repo or worktree from the wtw registry only (no git/disk changes).', 'Pairs with: wtw init (main repo), wtw add (worktree listing). For full worktree teardown use wtw remove.', '', 'Arguments:', '  name    Repo alias, path, worktree, or alias-task', '', 'Options:', '  --repo <name>   Disambiguate when the same task exists in multiple repos', '  --force         Skip confirmation') }
        'workspace'   { @('wtw workspace <name>', 'Generate a workspace file only (no git worktree).', '', 'Arguments:', '  name    Target repo/worktree') }
        'ws'          { @('wtw workspace <name>', 'Generate a workspace file only (no git worktree).', '', 'Arguments:', '  name    Target repo/worktree') }
        'copy'        { @('wtw copy <name>', 'Create a standalone copy of workspace from template.', '', 'Arguments:', '  name    Target repo/worktree') }
        'sync'        { @('wtw sync [name] [--all]', 'Re-apply template settings to managed workspaces.', '', 'Arguments:', '  name    Target workspace (alias, task, or file path; default: detected from cwd)', '', 'Options:', '  --all               Sync all managed workspaces', '  --repo <name>       Limit --all to a specific repo', '  --template <path>   Override template source', '  --dry-run           Show what would be synced without writing', '  --color-source      json | workspace (single-file sync; skips interactive prompt)', '                      Default when omitted: prompt if interactive, else json-first', '', 'Examples:', '  wtw sync                  Sync current workspace', '  wtw sync proj-fix         Sync a specific workspace by name', '  wtw sync --all            Sync all registered workspaces', '  wtw sync --all --repo proj Sync all workspaces for one repo') }
        'color'       { @('wtw color [name] [hex|random]', 'Set or show the Peacock color for a workspace.', '', 'Arguments:', '  name     Target workspace (default: detected from cwd)', '  color    A hex color (rrggbb) or "random" for max contrast', '', 'Options:', '  --no-sync   Skip syncing the workspace file after color change', '', 'Examples:', '  wtw color                  Show color for current workspace', '  wtw color proj random      Pick a maximally contrasting color', '  wtw color my-task e05d44   Set a specific color', '', 'Note: # starts a comment in PowerShell. Either omit it', '  or quote it: ''#e05d44''') }
        'clean'       { @('wtw clean', 'Remove stale AI-created worktrees that no longer have active branches.') }
        'agent'       { @('wtw agent profile set <repo> <profile>', 'Configure which agentctl profile wtw create applies for a repo.', '', 'Examples:', '  wtw agent profile set snowmain1 solo', '  wtw agent profile default team', '  wtw agent profile get snowmain1', '  wtw agent profile list') }
        'install'     { @('wtw install', 'Install or update wtw globally to ~/.wtw/module/.', '', 'Options:', '  --skip-profile  Skip modifying shell profile') }
        'update'      { @('wtw install', 'Install or update wtw globally to ~/.wtw/module/.', '', 'Options:', '  --skip-profile  Skip modifying shell profile') }
        'skill'       { @('wtw skill [--agent claude|agents|all]', 'Install the wtw AI skill into the current repo.', '', 'Copies skill definitions so AI agents (Claude, Codex, Cursor, Gemini)', 'can discover and use wtw commands.', '', 'Options:', '  --agent claude    Claude Code only (.claude/skills/)', '  --agent agents    Cross-agent format (.agents/skills/)', '  --agent all       Both (default)') }
        default {
            # Check if it's an editor command
            $resolved = Resolve-WtwEditorCommand $Command
            if ($resolved) {
                $displayName = if ($resolved -is [hashtable]) { $resolved.appName } else { $resolved }
                @("wtw $Command [name]", "Open workspace/directory in $displayName.", '', 'Arguments:', '  name    Target to open (default: detected from cwd)', '', 'Falls back to opening the directory if no workspace file exists.')
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
