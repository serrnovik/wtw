# wtw — Git Worktree + Workspace Manager

PowerShell 7+ module that manages git worktrees together with VS Code/Cursor `.code-workspace` files.

## Why

If you run several AI coding agents in parallel — say five at once — you already know the pain. Each one wants its own branch, and juggling `git worktree` from the shell gets old fast. Sometimes an agent creates a worktree for you; you still need to open it, wire it into your editor, and find it again tomorrow. Tracking what lives where becomes a job in itself.

Underneath the clutter, the deeper pain is context switching: which checkout, which branch, which editor window. wtw reduces that friction by automating worktree lifecycle and `.code-workspace` wiring, and by giving each workspace a distinct color so you can orient at a glance instead of decoding paths.

Git worktrees are the right primitive, but using them raw is tedious. Creating one properly means: `git worktree add`, then craft a `.code-workspace` file, configure folder paths, set up terminal profiles, and remember the path. Removing one means reversing all of that. This should be one command, not six.

Then there's the visual problem. With five workspaces open, they all look identical — same title bar, same activity bar, same terminal tabs. You alt-tab and have no idea where you landed. wtw auto-assigns a unique Peacock color from a 20-color palette so your title bar, activity bar, and status bar instantly tell you which branch you're in.

That's what wtw does: **one command, everything wired.**

- `wtw create auth` — git worktree, workspace file, unique color, shell aliases. Ready.
- `wtw auth` — switch to it.
- `wtw remove auth` — clean up worktree, workspace, branch, color. Gone.

No manual bookkeeping. No stale directories. No identical-looking windows.

## Prerequisites

- **PowerShell 7+** — required
- **Git** — required
- **[Peacock extension](https://marketplace.visualstudio.com/items?itemName=johnpapa.vscode-peacock)** — recommended for workspace colors in VS Code, Cursor, Windsurf, etc. `wtw install` will detect your editors and offer to install it.
- **iTerm2** (macOS) or **Windows Terminal** (Windows) — recommended for colored terminal tabs. wtw sets tab color automatically via escape sequences when switching worktrees. Other terminals get the window title but may not support tab colors.

## Install

### One-liner (recommended)

Checks for git and PowerShell 7+, installs them if missing, clones wtw, and runs `wtw install`.

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/serrnovik/wtw/main/install.sh | bash
```

**Windows** (from PowerShell):

```powershell
irm https://raw.githubusercontent.com/serrnovik/wtw/main/install.ps1 | iex
```

### From PowerShell Gallery

If you already have PowerShell 7+:

```powershell
Install-Module -Name wtw -Scope CurrentUser
Import-Module wtw
wtw install
```

### From source (git)

```powershell
git clone https://github.com/serrnovik/wtw.git
cd wtw
Import-Module ./wtw.psm1 -Force
wtw install
```

### What `wtw install` does

- Copies the module to `~/.wtw/module/`
- Sets up your shell profile (PowerShell, zsh, and/or bash)
- Detects installed editors (VS Code, Cursor, Windsurf, VSCodium, Antigravity)
- Offers to install the [Peacock extension](https://marketplace.visualstudio.com/items?itemName=johnpapa.vscode-peacock)
- Checks that git is available

Re-run `wtw install` from source after pulling updates.

## Quick Start

### 1. Register your repos

```powershell
cd ~/projects/my-app
wtw init "app,my-app"

cd ~/projects/api-service
wtw init "api,api-service" --template ./workspace.code-workspace.template
```

This generates a `.code-workspace` file for each repo and registers it in the global registry.

### 2. Create a worktree

```powershell
cd ~/projects/my-app
wtw create auth
```

This creates:
- Git worktree at `~/projects/my-app_auth/` (sibling to main repo)
- Branch `auth`
- Workspace file `my-app_auth.code-workspace` from your template
- Unique Peacock color

### 3. Work in it

```powershell
wtw auth                  # cd to worktree + run session script
wtw cursor auth           # open in Cursor (or: wtw cur auth)
wtw code auth             # open in VS Code (or: wtw co auth)
```

### 4. Done with it

```powershell
wtw remove auth           # removes worktree + workspace + branch
```

### 5. Clean up stale AI worktrees

```powershell
wtw clean --dry-run       # preview (codex, cursor, conductor worktrees)
wtw clean                 # interactive selection + removal
```

## Commands

| Command | Description |
|---------|-------------|
| `wtw init [aliases] [--template X]` | Register current repo (comma-separated aliases, optional shared template) |
| `wtw add [path] [--repo X --task X]` | Import an existing worktree into the registry |
| `wtw create <task> [--branch X] [--open] [--no-branch]` | Create worktree + workspace + branch |
| `wtw list [-d\|--detailed] [--repo alias]` | List all repos and worktrees with paths and aliases |
| `wtw <name>` | Switch to repo/worktree — implicit `go` (cd + session init) |
| `wtw go <name>` | Same as above, explicit |
| `wtw open [name] [--editor X]` | Open workspace in editor (defaults to current repo/worktree) |
| `wtw cursor [name]` | Open in Cursor (aliases: `cur`) |
| `wtw code [name]` | Open in VS Code (aliases: `co`) |
| `wtw antigravity [name]` | Open in Antigravity (aliases: `anti`, `ag`) |
| `wtw windsurf [name]` | Open in Windsurf (aliases: `wind`, `ws`) |
| `wtw codium [name]` | Open in VSCodium (aliases: `vscodium`) |
| `wtw sourcegit [name]` | Open in SourceGit (aliases: `sgit`, `sg`) |
| `wtw remove <task> [--force]` | Remove worktree + workspace + branch |
| `wtw workspace <name> [--main] [--worktree-path X]` | Generate workspace file only (no git worktree) |
| `wtw copy <name> [--code-folder X]` | Standalone workspace copy from template |
| `wtw color [name] [hex\|random]` | Set workspace color |
| `wtw sync --all [--dry-run] [--repo X]` | Re-apply template to all managed workspaces |
| `wtw clean [--dry-run] [--force]` | Clean stale AI worktrees (codex, cursor, conductor) |
| `wtw install [--skip-profile]` | Install/update globally to `~/.wtw/module/` |

## Importing Existing Worktrees

To import a worktree created by another tool (codex, cursor, manually) into the registry:

```powershell
# From inside the worktree (auto-detects parent repo):
cd /path/to/worktree
wtw add
# → Detected parent repo: my-app
# → prompts for task name

# Or from anywhere, with explicit params:
wtw add /path/to/worktree --repo my-app --task my-feature
```

After importing, the worktree appears in `wtw list` and you can use `wtw go my-feature`.

## Name Resolution

All commands that accept a target name (`go`, `open`, `remove`, editor shortcuts, and the implicit go) share the same resolution logic via `Resolve-WtwTarget`:

1. **Exact repo alias** — `app` goes to main repo
2. **alias-task format** — `app-auth` resolves to repo `app` + worktree `auth`
3. **Bare task name** — `auth` searches all repos (works if unambiguous)

Multiple aliases per repo: `wtw init "app, my-app"` registers both.

After `wtw create auth`, all these work:
```powershell
wtw auth              # implicit go (task name)
wtw app-auth          # alias-task format
wtw go auth           # explicit go
wtw remove app-auth   # remove using alias-task format
wtw cursor app-auth   # open in Cursor
app-auth              # shell alias (after terminal restart)
```

## Templates

Templates define the shared workspace structure and use `{{WTW_*}}` placeholders:

```json
{
  "folders": [
    { "name": "{{WTW_WORKSPACE_NAME}}", "path": "{{WTW_CODE_FOLDER}}" },
    { "path": "../shared-tools" }
  ],
  "settings": {
    "terminal.integrated.cwd": "${workspaceFolder:{{WTW_WORKSPACE_NAME}}}",
    ...
  }
}
```

| Placeholder | Replaced with |
|-------------|---------------|
| `{{WTW_WORKSPACE_NAME}}` | Workspace name (e.g., `my-app_auth`) |
| `{{WTW_CODE_FOLDER}}` | Absolute path to the worktree |

Colors (`workbench.colorCustomizations`, `peacock.color`) are **not** in the template — wtw injects them automatically from the color palette.

### Sharing templates across repos

Multiple repos can share a template for consistent terminal profiles, extra folders, and editor settings:

```powershell
# Two repos share the same workspace structure:
wtw init "app,my-app" --template ./templates/shared.code-workspace.template
wtw init "api,api-service" --template ./templates/shared.code-workspace.template

# A third repo has a different structure:
wtw init "dash,dashboard" --template ./templates/dashboard.code-workspace.template
```

### Syncing after template changes

When you update a template (add a folder, change a setting), re-apply it:

```powershell
wtw sync --all --dry-run    # preview what would change
wtw sync --all              # apply to all repos + worktrees
wtw sync --all --repo app   # apply to one repo only
```

### Legacy support

If `--template` points to a real `.code-workspace` file (no `{{WTW_*}}` placeholders), wtw falls back to regex replacement of folder paths and `${workspaceFolder:X}` references.

## List Output

### Standard view

`wtw list` shows all registered repos and their worktrees in a compact table. The **Color** column renders with actual ANSI true-color backgrounds in supported terminals:

```
  Kind  Repo         Aliases                Branch          Color    Path                              Workspace
  ----  -----------  ---------------------  --------------  -------  --------------------------------  ----------------------------
  repo  my-app       app, my-app            main            #2285a6  /home/user/projects/my-app        my-app.code-workspace
    wt               app-auth, my-app-auth  auth            #e05d44  /home/user/projects/my-app_auth   my-app_auth.code-workspace
  repo  api-service  api, api-service       develop         #97ca00  /home/user/projects/api-service   api-service.code-workspace
```

- **Kind**: `repo` = main repo, `wt` = worktree (indented)
- **Aliases**: what you type in `wtw go` / `wtw cursor` / shell shortcuts
- **Color**: rendered as a colored swatch with contrasting text

### Detailed view

`wtw list --detailed` (or `wtw list -d`) shows a card-style layout with:
- Repo names rendered as full-width colored badges
- Worktree entries with color dot indicators
- Clickable `file://` hyperlinks on paths (in terminals that support OSC 8)
- A **Settings** section at the bottom with clickable links to all config files

```
  ╔══════════════════════════════════════════╗
  ║  wtw — Worktree & Workspace Registry     ║
  ╚══════════════════════════════════════════╝

    my-app    main
    Aliases   : app, my-app
    Path      : /home/user/projects/my-app
    Workspace : my-app.code-workspace

      ██ auth
      Aliases   : app-auth, my-app-auth
      Path      : /home/user/projects/my-app_auth
      Workspace : my-app_auth.code-workspace

  ─── Settings ───
    Registry : ~/.wtw/registry.json
    Colors   : ~/.wtw/colors.json
    Config   : ~/.wtw/config.json
```

## Config

All config lives in `~/.wtw/`:

| File | Purpose |
|------|---------|
| `config.json` | Editor preference, workspaces dir, stale paths to scan |
| `registry.json` | Registered repos, aliases, template paths, worktrees |
| `colors.json` | 20-color palette + per-worktree color assignments |
| `module/` | Globally installed module copy |

## Worktree Layout

Worktrees are created as siblings to the main repo, named `{registryKey}_{task}`:

```
~/projects/
├── my-app/               # main repo
├── my-app_auth/          # worktree: wtw create auth
├── my-app_billing/       # worktree: wtw create billing
├── api-service/          # another repo
├── api-service_hotfix/   # worktree: wtw create hotfix (from api)
```

## Workspace Files

Generated in the configured `workspacesDir` (default: `~/code-workspaces/`):

```
~/code-workspaces/
├── my-app.code-workspace             # main repo (generated by wtw init)
├── my-app_auth.code-workspace        # generated by wtw create auth
├── my-app_billing.code-workspace     # generated by wtw create billing
```

Each generated workspace:
- Points to the worktree as the code folder
- Keeps extra folders from template
- Gets a unique Peacock color from the 20-color palette
- Has terminal profiles pointing to the correct `${workspaceFolder:X}`
- Stores `wtw.*` metadata in settings for sync support

## Colors

20-color palette auto-assigned per worktree. Colors are recycled when worktrees are removed. Colors are applied to:
- **Editor** — VS Code/Cursor/Windsurf/VSCodium Peacock color customizations (title bar, activity bar, status bar) via the [Peacock extension](https://marketplace.visualstudio.com/items?itemName=johnpapa.vscode-peacock)
- **Terminal tabs** — iTerm2 and Windows Terminal tab colors, set automatically via escape sequences when you `wtw go` into a worktree

## Startup Scripts

When you `wtw go <name>`, wtw changes to the worktree directory and then:

1. If a **startup script** is configured (via `--startup-script` on `wtw init` or auto-detected), it runs that script. The script can handle terminal coloring, environment setup, etc.
2. If **no startup script** is found, wtw sets the terminal tab color and window title itself using escape sequences (iTerm2, Windows Terminal).

Auto-detected script names: `start-repository-session.ps1`, `start-tools-session.ps1`.

```powershell
# Register with a custom startup script:
wtw init "app" --startup-script my-session-init.ps1

# Or let wtw auto-detect (looks for start-repository-session.ps1):
wtw init "app"

# Worktrees inherit the startup script from their parent repo.
```

## Profile Integration

`wtw install` adds a loader to your PowerShell profile. On shell startup, `Register-WtwProfile` creates shortcut aliases from the registry:

```powershell
app              # same as: wtw go app
app-auth         # same as: wtw go app-auth
my-app           # same as: wtw go my-app
my-app-auth      # same as: wtw go my-app-auth
```

New worktrees get aliases after terminal restart. Within the current session, use `wtw <name>` directly.

## Alias Collision Protection

`wtw init` rejects aliases already used by another repo:

```
wtw init "app,duplicate"
# Error: Alias 'app' is already used by repo 'my-app'. Choose different aliases.
```

## Git Hooks in Worktrees

Worktrees share hooks with the main repo (`.git` is a file in worktrees, not a directory). Session scripts detect this and skip hook installation for worktrees.

## Shell Integration

wtw is a PowerShell module, but you don't need to use pwsh as your daily shell. Thin wrappers for **zsh** and **bash** delegate to pwsh for all logic while handling `cd` and terminal colors natively.

### Setup

`wtw install` detects your shell and offers to add the loader:

| Shell | Config file | Loader |
|-------|------------|--------|
| **PowerShell** | `$PROFILE` | Module import + `Register-WtwProfile` (automatic) |
| **zsh** | `~/.zshrc` | `source ~/.wtw/shell/wtw.zsh` |
| **bash** | `~/.bashrc` | `source ~/.wtw/shell/wtw.bash` |

### What runs where

| Command | zsh/bash | pwsh |
|---------|----------|------|
| `wtw go <name>` / `wtw <name>` | `cd` + terminal color (native) | Name resolution (subprocess) |
| Shell aliases (`app-auth`) | `cd` + terminal color (native) | Pre-generated at shell startup |
| `wtw list`, `wtw create`, etc. | Passthrough | Full logic |

The pwsh subprocess adds ~400ms latency to `wtw go`. Pre-generated shell aliases are instant.

### Terminal Color Support

| Terminal | Tab color | Window title | Platform |
|----------|-----------|-------------|----------|
| **iTerm2** | Yes | Yes | macOS |
| **Windows Terminal** | Yes | Yes | Windows |
| **Kitty** | Yes | Yes | Linux/macOS |
| **Konsole** | Yes | Yes | Linux (KDE) |
| **tmux** | Pane border color | Pane title | All |
| **WezTerm** | Via user var | Yes | All |
| Terminal.app | No | Yes | macOS |
| GNOME Terminal | No | Yes | Linux |
| Alacritty | No | Yes | All |
| cmd.exe / PowerShell console | No | Yes | Windows |

Terminals without tab color support still get the window title set, which helps with orientation when alt-tabbing.

## Cross-Platform

Works on macOS, Windows, and Linux with PowerShell 7+. Uses `Join-Path` everywhere, `du -sk` for fast size scanning on Unix (falls back to `Get-ChildItem` on Windows). zsh and bash wrappers available for non-PowerShell daily drivers.
