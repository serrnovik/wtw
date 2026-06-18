# wtw — Git Worktree + Workspace Manager

PowerShell 7+ module that manages git worktrees together with VS Code/Cursor `.code-workspace` files.

## Why

If you run several AI coding agents in parallel — say five at once — you already know the pain. Each one wants its own branch, and juggling `git worktree` from the shell gets old fast. Sometimes an agent creates a worktree for you; you still need to open it, wire it into your editor, and find it again tomorrow. Tracking what lives where becomes a job in itself.

Underneath the clutter, the deeper pain is context switching: which checkout, which branch, which editor window. wtw reduces that friction by automating worktree lifecycle and `.code-workspace` wiring, and by giving each workspace a distinct color so you can orient at a glance instead of decoding paths.

Git worktrees are the right primitive, but using them raw is tedious. Creating one properly means: `git worktree add`, then craft a `.code-workspace` file, configure folder paths, set up terminal profiles, and remember the path. Removing one means reversing all of that. This should be one command, not six.

Then there's the visual problem. With five workspaces open, they all look identical — same title bar, same activity bar, same terminal tabs. You alt-tab and have no idea where you landed. wtw auto-assigns a unique Peacock color from a 20-color palette so your title bar, activity bar, and status bar instantly tell you which branch you're in.

That's what wtw does: **one command, everything wired.**

- `wtw create auth` — git worktree, workspace file, unique color, shell aliases, and optional AI-tool project registration. Ready.
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
- Codex Desktop project metadata, if Codex is installed/present

### 3. Work in it

```powershell
wtw auth                  # cd to worktree + run session script
wtw cursor auth           # open in Cursor (or: wtw cur auth)
wtw code auth             # open in VS Code (or: wtw co auth)
wtw codex auth            # open the worktree in Codex Desktop
wtw codex auth --skip-restart  # open without closing Codex if the label needs repair
wtw cmux auth             # open the worktree as a cmux workspace (or: wtw cm auth)
wtw wmux auth             # Windows: open the worktree as a wmux workspace (or: wtw wm auth)
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
| `wtw init [aliases] [--template X] [--startup-script X] [--startup-script-zsh X] [--startup-script-bash X]` | Register current repo with aliases, template, and per-shell session scripts |
| `wtw add [path] [--repo X --task X]` | Import an existing worktree into the registry |
| `wtw create <task> [--branch X] [--open] [--no-branch]` | Create worktree + workspace + branch |
| `wtw list [-d\|--detailed] [--wide] [--repo alias]` | List repos/worktrees: default **compact** table (`--wide` = full aliases and paths) |
| `wtw <name>` | Switch to repo/worktree — implicit `go` (cd + session init) |
| `wtw go <name>` | Same as above, explicit |
| `wtw open [name] [--editor X]` | Open workspace in editor (defaults to current repo/worktree) |
| `wtw cursor [name]` | Open in Cursor (aliases: `cur`) |
| `wtw code [name]` | Open in VS Code (aliases: `co`) |
| `wtw antigravity [name]` | Open in Antigravity (aliases: `anti`, `ag`) |
| `wtw windsurf [name]` | Open in Windsurf (aliases: `wind`, `ws`) |
| `wtw codium [name]` | Open in VSCodium (aliases: `vscodium`) |
| `wtw codex [name] [--skip-restart]` | Open in Codex Desktop |
| `wtw cmux [name]` | Open the worktree as a cmux workspace (aliases: `cm`) |
| `wtw wmux [name]` | Open the worktree as a wmux workspace on Windows (aliases: `wm`) |
| `wtw sourcegit [name]` | Open in SourceGit (aliases: `sgit`, `sg`) |
| `wtw remove <task> [--force]` | Remove worktree + workspace + branch |
| `wtw workspace <name> [--main] [--worktree-path X]` | Generate workspace file only (no git worktree) |
| `wtw copy <name> [--code-folder X]` | Standalone workspace copy from template |
| `wtw color [name] [hex\|random]` | Set workspace color |
| `wtw sync --all [--dry-run] [--repo X]` | Re-apply template to all managed workspaces |
| `wtw clean [--dry-run] [--force]` | Clean stale AI worktrees (codex, cursor, conductor) |
| `wtw install [--skip-profile]` | Install/update globally to `~/.wtw/module/` |
| `wtw skill [--agent claude\|agents\|all]` | Install AI skill into current repo for agent support |

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

Multiple aliases per repo: `wtw init "app,my-app"` registers both.

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
| `{{WTW_ENV_XYZ}}` | Value of the `XYZ` environment variable on the host machine. If `XYZ` is not set, the entire folder block containing this placeholder is safely skipped and omitted from the generated workspace file. |

Colors (`workbench.colorCustomizations`, `peacock.color`) are **not** in the template — wtw injects them automatically from the color palette.

### Template resolution

`wtw init` chooses the workspace template in this order:

1. `--template <alias|path>` when provided.
2. An existing `<repo>.code-workspace` in the configured workspaces directory.
3. A repo-shipped template under `configs/workspace-templates/` when one can be
   resolved by repo name, repo name without trailing digits, or as the only
   template in that directory.
4. The bundled minimal template from
   `devops/worktree-workspace/templates/minimal.code-workspace.template`.

The minimal fallback contains only the active code folder and empty settings;
wtw still injects Peacock colors and `wtw.*` metadata, so fresh installs get
usable colored workspaces even when a repo has no custom template.

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

`wtw list` shows registered repos and worktrees in a **compact** table so terminal width stays usable:

- **Task**: worktree slug ( `-` on the main repo row ).
- **Aliases**: in **wide** mode (and detailed view), each alias is on its own line inside the cell. In **compact** mode, worktrees show one `alias-task` line; the main repo shows up to two alias lines plus a `(+N)` line when more aliases exist.
- **Branch**: truncated with an ellipsis when very long.
- **Path**: `$HOME` shortened to `~`, with a middle ellipsis when still long.

Use **`wtw list --wide`** for the previous density on paths and branches, with **every** alias permutation listed (still **one alias per line** in the Aliases column). The **Color** column uses ANSI true-color swatches; for color hex cells, the swatch appears only on the first sub-line of a row.

Example (values abbreviated; alias cells may span several screen lines):

```text
  Kind  Repo    Task   Aliases       Branch       Color    Path              Workspace
  ----  ------  -----  ----------    -----------  -------  ----------------  ------------------
  repo  my-app  -      app           main         (swatch)  ~/projects/...    my-app.code-workspace
                      my-app
                      (+1)
  wt    my-app  auth   app-auth      auth-branch  (swatch)  ~/projects/...    my-app_auth.code-workspace
```

- **Kind**: `repo` = main repo, `wt` = worktree
- **Aliases** (compact): primary match target; use `--wide` for the full cross-product list
- **Color**: colored swatch with contrasting text

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
    Aliases   : app
                my-app
    Path      : /home/user/projects/my-app
    Workspace : my-app.code-workspace

      ██ auth
      Aliases   : app-auth
                my-app-auth
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

### agentctl profile overlays

When an optional `agentctl`-compatible helper is installed on `PATH`,
`wtw create` attaches a local AI-agent overlay inside the new worktree:

```text
.agent.local/personal.md
.agent.local/PLAN.md
CLAUDE.local.md
```

This integration is best-effort and skipped when `agentctl` is not installed.
WTW does not vendor `agentctl` or profile content. For open-source use,
`agentctl` is just a local executable hook with this tiny contract:

```powershell
agentctl repo attach --profile <profile>
```

The helper decides what profiles mean and what ignored local files to create.

Profile resolution is intentionally conservative:

1. `registry.json` repo entry `agentctlProfile`
2. `config.json` `agentctl.repoProfiles.<repoName>`
3. `config.json` `agentctl.defaultProfile`
4. fallback: `team`

Example `~/.wtw/config.json` fragment:

```json
{
  "agentctl": {
    "enabled": true,
    "defaultProfile": "team",
    "repoProfiles": {
      "snowmain1": "solo",
      "everix1": "team"
    }
  }
}
```

Set these values through WTW:

```powershell
wtw agent profile set snowmain1 solo
wtw agent profile set e1 team
wtw agent profile default team
wtw agent profile list
```

Repo aliases are accepted and stored under the canonical WTW repo name.

Set `"enabled": false` to disable the integration globally.

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

## AI Tool Integrations

When optional tools are installed, `wtw create` registers the new worktree with
them and `wtw remove` cleans that registration up:

- **Codex Desktop** — trusts the worktree path in `~/.codex/config.toml`, keeps
  a minimal `.codex/config.toml` in the worktree when one is missing, and
  pre-seeds the saved sidebar label in
  `~/.codex/.codex-global-state.json` from the same `--name`/pretty name and
  color-circle prefix used by Superset/SourceGit when Codex is not running.
  When Codex is already running, `wtw codex <name>` prompts to close/relaunch it
  around the label write so the app does not overwrite the external state edit.
  It skips that prompt when the saved label already matches; pass
  `--skip-restart` to open without repairing a missing/stale label.
- **Superset** — creates/removes a local workspace named from the same pretty
  name when the Superset CLI is installed and the repo project can be matched.
- **SourceGit** — adds/removes the worktree from managed repositories when
  SourceGit is installed.
- **cmux** — `wtw cmux <name>` (alias `wtw cm <name>`) selects an existing live
  cmux workspace for the worktree's path, or creates one via
  `cmux new-workspace --name <pretty> --cwd <path>`. `wtw create` registers a
  Command-Palette workspace entry in `~/.config/cmux/cmux.json`, and
  `wtw remove` cleans that entry up. Inside cmux terminals, the `wtw.bash` /
  `wtw.zsh` shell init stamps the worktree's pretty name, color, and a
  `wtw:<repo>/<task>` status pill onto the surrounding cmux workspace. All of
  this is a no-op when the cmux CLI is not installed.
- **wmux** — `wtw wmux <name>` (alias `wtw wm <name>`) is recognized on
  Windows, but active workspace open/registration is disabled for current wmux
  builds because the CLI workspace/surface commands are not reliable enough for
  wtw automation. Keep the shortcut/resolver in place for the substrate/API work
  tracked upstream in `openwong2kim/wmux#15`.
- **agentctl** — when installed, attaches ignored local AI-agent overlay files
  to the new worktree using the configured profile. Defaults to `team` for
  safety unless a repo/global override selects another profile.

## Colors

20-color palette auto-assigned per worktree. Colors are recycled when worktrees are removed. Colors are applied to:
- **Editor** — VS Code/Cursor/Windsurf/VSCodium Peacock color customizations (title bar, activity bar, status bar) via the [Peacock extension](https://marketplace.visualstudio.com/items?itemName=johnpapa.vscode-peacock)
- **Terminal tabs** — iTerm2 and Windows Terminal tab colors, set automatically via escape sequences when you `wtw go` into a worktree

## Startup Scripts

When you `wtw go <name>`, wtw changes to the worktree directory, sets the terminal tab color and title, and then runs the startup script if one is configured.

### Script detection

wtw detects the interpreter from the file extension:

| Extension | In pwsh session | In zsh/bash session |
|-----------|----------------|---------------------|
| `.ps1` | Runs with pwsh | Runs with pwsh (subprocess) |
| `.zsh` | N/A | Sourced in zsh |
| `.sh`, `.bash` | N/A | Sourced in current shell |

### Per-shell overrides

You can set different scripts for different shells. The zsh/bash wrappers check for a per-shell override first, then fall back to the default:

```powershell
# Default script (used by pwsh, and by zsh/bash if no override)
wtw init "app" --startup-script start-repository-session.ps1

# Zsh-specific session script (sourced when switching from zsh)
wtw init "app" --startup-script-zsh start-session.zsh

# Bash-specific session script
wtw init "app" --startup-script-bash start-session.sh

# All at once
wtw init "app" --startup-script start-repo.ps1 --startup-script-zsh start-session.zsh
```

This is stored in the registry as:

```json
{
  "sessionScript": "start-repository-session.ps1",
  "sessionScripts": {
    "zsh": "start-session.zsh",
    "bash": "start-session.sh"
  }
}
```

### Auto-detection

If no `--startup-script` is provided, wtw looks for these files in the repo root: `start-repository-session.ps1`, `start-tools-session.ps1`.

Worktrees inherit the startup script from their parent repo.

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

## Dev Environment Integration

### Philosophy

wtw's surface is lean: it manages worktrees, workspaces, colors, and shell aliases. It does **not** know about ports, namespaces, databases, or deployment — that's your build tool's job.

What wtw does is **tag the session** with environment variables that your build tool can read. If the variable is set, your deploy scripts can isolate. If not, they run shared. Zero config for the common case, opt-in isolation when you need it.

### Environment variables

When you `wtw go auth` (or use a shell alias), wtw exports:

| Variable | Example (worktree `auth`, index 1) | Example (main repo) |
|----------|-----------------------------------|--------------------|
| `WTW_WORKTREE_ID` | `auth` | *(empty)* |
| `WTW_WORKTREE_INDEX` | `1` | *(empty)* |
| `DEV_WORKTREE_ID` | `auth` | *(empty)* |
| `DEV_WORKTREE_INDEX` | `1` | `0` |
| `DEV_WORKTREE_DASHED_POSTFIX` | `-auth` | *(empty)* |
| `DEV_WORKTREE_PORT_OFFSET` | `100` | `0` |

The `WTW_*` vars are wtw-specific. The `DEV_WORKTREE_*` vars are **generic and tool-agnostic** — any build system, task runner, or deploy script can use them without depending on wtw.

### How build tools consume them

The key insight: `DEV_WORKTREE_DASHED_POSTFIX` is either `-auth` or empty string. So config that appends it works unchanged for both isolated and shared mode:

**Namespace isolation** (config file with env var expansion):
```yaml
# Your build config — namespace includes worktree suffix when set, empty otherwise
kubernetes:
  namespace: "myapp${DEV_WORKTREE_DASHED_POSTFIX}"
  # → "myapp-auth" (worktree) or "myapp" (main)
```

**Port isolation** (in a deploy script):
```bash
BASE_PORT=31632
PORT=$((BASE_PORT + ${DEV_WORKTREE_PORT_OFFSET:-0}))
# → 31732 (worktree index 1) or 31632 (main)
```

```powershell
# Same in PowerShell:
$port = 31632 + [int]($env:DEV_WORKTREE_PORT_OFFSET ?? '0')
```

**Docker Compose** (in `.env` or directly):
```yaml
services:
  postgres:
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
```
```bash
# Set before docker compose up:
export POSTGRES_PORT=$((5432 + ${DEV_WORKTREE_PORT_OFFSET:-0}))
```

### Index assignment

The worktree index is determined by registry order (1-based, sequential per repo). Main repo is always index 0. The index is stable — it doesn't change when other worktrees are added or removed, only when the worktree itself is created.

## Cross-Platform

Works on macOS, Windows, and Linux with PowerShell 7+. Uses `Join-Path` everywhere, `du -sk` for fast size scanning on Unix (falls back to `Get-ChildItem` on Windows). zsh and bash wrappers available for non-PowerShell daily drivers.
