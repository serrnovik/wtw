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
        { $_ -in 'edit', 'rename', 'ren' } {
            @(
                'wtw edit [name] [new-name] [options]',
                'Edit a registry record. Does not move git worktrees or rename branches.',
                'No flags: print the current record (cwd when name is omitted).',
                '',
                'Arguments:',
                '  name        Target (same resolution as wtw go). Default: cwd',
                '  new-name    Shorthand for --name',
                '',
                'Worktree options:',
                '  --name <pretty>   Display name (list/info, editor sidebars). Color circle is kept.',
                '  --task <key>      Registry key used by `wtw go` and aliases (sn-<key>)',
                '',
                'Repo options:',
                '  --alias a,b       Replace typed aliases',
                '  --name a,b        Same as --alias when the target is a repo',
                '  --key <name>      Registry key (also remaps color assignments)',
                '',
                'Shared:',
                '  --repo <name>     Disambiguate when the same task exists in multiple repos',
                '  --no-sync         Skip workspace-file rewrite and SourceGit bookmark',
                '',
                'Aliases: wtw rename, wtw ren',
                '',
                'Examples:',
                '  wtw edit                         Show the current record',
                '  wtw edit auth --name "Login"     Change the worktree display name',
                '  wtw rename auth login            Same as --name login',
                '  wtw edit auth --task login       Retarget wtw go login',
                '  wtw edit snowmain1 --alias sn,sm Replace repo aliases'
            )
        }
        'workspace'   { @('wtw workspace <name>', 'Generate a workspace file only (no git worktree).', '', 'Arguments:', '  name    Target repo/worktree') }
        'ws'          { @('wtw workspace <name>', 'Generate a workspace file only (no git worktree).', '', 'Arguments:', '  name    Target repo/worktree') }
        'copy'        { @('wtw copy <name>', 'Create a standalone copy of workspace from template.', '', 'Arguments:', '  name    Target repo/worktree') }
        'sync'        { @('wtw sync [name] [--all]', 'Re-apply template settings to managed workspaces.', '', 'Arguments:', '  name    Target workspace (alias, task, or file path; default: detected from cwd)', '', 'Options:', '  --all               Sync all managed workspaces', '  --repo <name>       Limit --all to a specific repo', '  --template <path>   Override template source', '  --dry-run           Show what would be synced without writing', '  --color-source      json | workspace (single-file sync; skips interactive prompt)', '                      Default when omitted: prompt if interactive, else json-first', '', 'Examples:', '  wtw sync                  Sync current workspace', '  wtw sync proj-fix         Sync a specific workspace by name', '  wtw sync --all            Sync all registered workspaces', '  wtw sync --all --repo proj Sync all workspaces for one repo') }
        'color'       { @('wtw color [name] [hex|random]', 'Set or show the Peacock color for a workspace.', '', 'Arguments:', '  name     Target workspace (default: detected from cwd)', '  color    A hex color (rrggbb) or "random" for max contrast', '', 'Options:', '  --no-sync   Skip syncing the workspace file after color change', '', 'Examples:', '  wtw color                  Show color for current workspace', '  wtw color proj random      Pick a maximally contrasting color', '  wtw color my-task e05d44   Set a specific color', '', 'Note: # starts a comment in PowerShell. Either omit it', '  or quote it: ''#e05d44''') }
        'clean'       { @('wtw clean', 'Remove stale AI-created worktrees that no longer have active branches.') }
        'host'        { @(
            'wtw host [list|show|discover|add|remove|sync|trust|test] [name] [options]',
            'Manage the remote machines `wtw --on <host>` can open worktrees on.',
            '',
            'Hosts live in ~/.wtw/config.json and are mirrored into ~/.ssh/config.d/wtw,',
            'because the editor''s Remote-SSH extension resolves hosts through the ssh',
            'client rather than through wtw.',
            '',
            'Subcommands:',
            '  list              One line per host: active address, transport, ssh status',
            '  show [name]       Full config: every candidate, its transport and whether',
            '                    it is up, which one is active, and ssh-config conflicts',
            '  discover          Register machines found on your tailnet (Tailscale)',
            '                    --yes to skip the prompt, --exclude a,b to ignore for good',
            '  add <name>        Add or update a host, then sync ssh config',
            '  remove <name>     Drop a host, then sync ssh config',
            '  sync              Re-probe addresses, rewrite ~/.ssh/config.d/wtw',
            '  trust <name>      Show host-key fingerprints, then add to known_hosts',
            '  test <name>       Probe addresses, ssh config, and the remote wtw',
            '',
            'Transports are detected from the address itself:',
            '  tailscale  *.ts.net or 100.64.0.0/10      mdns   *.local',
            '  zerotier   a subnet this machine joined   lan    RFC1918 address',
            '',
            'Options for add:',
            '  --alias a,b            Short names (wtw --on at ...)',
            '  --user <u>             SSH user',
            '  --address <ip|dns>     HostName for ssh',
            '  --identity <path>      IdentityFile (also sets IdentitiesOnly)',
            '  --port <n>             SSH port',
            '  --platform <p>         windows | linux | macos  (drives remote path translation)',
            '  --wtw <cmd>            Command used to invoke wtw remotely (default: wtw)',
            '  --pwsh <path>          Explicit pwsh path, when the probe list misses it',
            '  --emoji <char>         Per-machine emoji for terminal titles (e.g. a snowflake)',
            '  --label <short>        Short machine label (default: shortest alias, upper-cased)',
            '  --separator <s>        Between label and worktree (default: "."; try " " or "")',
            '  --via <transport>      Prefer tailscale|zerotier|mdns|lan (default: any).',
            '                         A preference reorders the candidates; it never makes',
            '                         the host unreachable when that transport is down.',
            '',
            'Only the options you pass are written, so `wtw host add x --platform windows`',
            'is a targeted edit rather than a reset of the other fields.',
            '',
            'Example:',
            '  wtw host add workstation --alias at --user dev --address 192.168.1.10 \',
            '      --identity ~/.ssh/id_ed25519_workstation --platform windows'
        ) }
        'agent'       { @('wtw agent profile set <repo> <profile>', 'Configure which agentctl profile wtw create applies for a repo.', '', 'Examples:', '  wtw agent profile set snowmain1 solo', '  wtw agent profile default team', '  wtw agent profile get snowmain1', '  wtw agent profile list') }
        'install'     { @('wtw install', 'Install or update wtw globally to ~/.wtw/module/.', '', 'Options:', '  --skip-profile  Skip modifying shell profile') }
        'update'      { @('wtw install', 'Install or update wtw globally to ~/.wtw/module/.', '', 'Options:', '  --skip-profile  Skip modifying shell profile') }
        'skill'       { @('wtw skill [--agent claude|agents|all]', 'Install the wtw AI skill into the current repo.', '', 'Copies skill definitions so AI agents (Claude, Codex, Cursor, Gemini)', 'can discover and use wtw commands.', '', 'Options:', '  --agent claude    Claude Code only (.claude/skills/)', '  --agent agents    Cross-agent format (.agents/skills/)', '  --agent all       Both (default)') }
        { $_ -in 'claudecode', 'ccode' } {
            @('wtw claudecode [name] [--prompt <text>]', 'Start a new Claude Code chat in the Claude desktop app, rooted at the target.', '', 'Arguments:', '  name    Target to open (default: detected from cwd)', '', 'Options:', '  --prompt <text>   Pre-fill the new chat''s composer (not submitted)', '', 'Uses the app''s claude://code/new deep link. The desktop app names sessions', 'itself (auto-titled from the first message, renameable in the UI), so wtw', 'cannot set a chat title the way it labels Cursor/ChatGPT projects.', '', 'Use `wtw claude` to just bring the Claude app forward instead.')
        }
        { $_ -in 't3', 't3code' } {
            @('wtw t3 [name]', 'Register a target as a T3 Code project, then launch T3 Code.', '', 'Arguments:', '  name    Target to register (default: detected from cwd)', '', 'T3 Code ships no CLI and no folder-open deep link, so wtw cannot tell a', 'running app to open a directory. Instead it appends the project to T3''s', 'event store under the wtw pretty name, so the worktree is already in the', 'sidebar when the app comes up.', '', 'Registration only runs while T3 Code is stopped — its server owns the', 'store while running. When it is up, wtw points T3''s "Add project starts', 'in" setting at the worktree instead.', '', 'T3 Code has no project color, so `wtw color` does not reach it.')
        }
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
