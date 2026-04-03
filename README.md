# wtw — Git Worktree + Workspace Manager

PowerShell 7+ module that manages git worktrees together with VS Code/Cursor `.code-workspace` files.

## Install

```powershell
# From inside the repo containing this module:
Import-Module ./devops/worktree-workspace/wtw.psm1 -Force
wtw install
```

This copies the module to `~/.wtw/module/` and adds a loader to your PowerShell profile.
Re-run `wtw install` from the repo source after pulling updates. Running `wtw install` from the global copy is blocked (it would delete itself).

## Quick Start

### 1. Register your repos

```powershell
cd ~/Data/snogit/snowmain3
wtw init "sn3,snowmain3" --template ./configs/workspace-templates/snowmain.code-workspace.template

cd ~/Data/snogit/snowmain2
wtw init "sn2,snowmain2" --template ./configs/workspace-templates/snowmain.code-workspace.template
```

This generates a `.code-workspace` file for each repo and registers it in the global registry.

### 2. Create a worktree

```powershell
cd ~/Data/snogit/snowmain3
wtw create auth
```

This creates:
- Git worktree at `~/Data/snogit/snowmain3_auth/` (sibling to main repo)
- Branch `auth`
- Workspace file `snowmain3_auth.code-workspace` from your template
- Unique Peacock color
- Superset project (if installed)

### 3. Work in it

```powershell
wtw auth                  # cd to worktree + run session script
wtw cursor auth           # open in Cursor (or: wtw cur auth)
wtw code auth             # open in VS Code (or: wtw co auth)
```

### 4. Done with it

```powershell
wtw remove auth           # removes worktree + workspace + branch + Superset project
```

### 5. Clean up stale AI worktrees

```powershell
wtw clean --dry-run       # preview (codex, cursor, superset worktrees)
wtw clean                 # interactive selection + removal
```

## Commands

| Command | Description |
|---------|-------------|
| `wtw init [aliases] [--template X]` | Register current repo (comma-separated aliases, optional shared template) |
| `wtw add [path] [--repo X --task X]` | Import an existing worktree into the registry |
| `wtw create <task> [--branch X] [--open] [--no-branch]` | Create worktree + workspace + branch |
| `wtw list [--repo alias]` | List all repos and worktrees with paths and aliases |
| `wtw <name>` | Switch to repo/worktree — implicit `go` (cd + session init) |
| `wtw go <name>` | Same as above, explicit |
| `wtw open [name] [--editor X]` | Open workspace in editor (defaults to current repo/worktree) |
| `wtw cursor [name]` | Open in Cursor (aliases: `cur`) |
| `wtw code [name]` | Open in VS Code (aliases: `co`) |
| `wtw antigravity [name]` | Open in Antigravity (aliases: `anti`, `ag`) |
| `wtw sourcegit [name]` | Open in SourceGit (aliases: `sgit`, `sg`) |
| `wtw remove <task> [--force]` | Remove worktree + workspace + branch |
| `wtw workspace <name> [--main] [--worktree-path X]` | Generate workspace file only (no git worktree) |
| `wtw copy <name> [--code-folder X]` | Standalone workspace copy from template |
| `wtw sync --all [--dry-run] [--repo X]` | Re-apply template to all managed workspaces |
| `wtw clean [--dry-run] [--force]` | Clean stale AI worktrees (codex, cursor, superset) |
| `wtw install [--skip-profile]` | Install/update globally to `~/.wtw/module/` |

## Importing Existing Worktrees

To import a worktree created by another tool (codex, cursor, manually) into the registry:

```powershell
# From inside the worktree (auto-detects parent repo):
cd /Users/sno/.codex/worktrees/c6b4/snowmain3
wtw add
# → Detected parent repo: snowmain3
# → prompts for task name

# Or from anywhere, with explicit params:
wtw add /path/to/worktree --repo snowmain3 --task my-feature
```

After importing, the worktree appears in `wtw list` and you can use `wtw go my-feature`.

## Name Resolution

Name resolution applies to `go`, `open`, editor shortcuts, and the implicit go:

- `sn3` — repo alias, goes to main repo
- `sn3-auth` — alias-task, goes to worktree
- `auth` — task name (works if unambiguous across repos)
- Multiple aliases per repo: `wtw init "sn3, snowmain3"` registers both

After `wtw create auth`, all these work:
```powershell
wtw auth              # implicit go (task name)
wtw sn3-auth          # alias-task format
wtw go auth           # explicit go
wtw cursor sn3-auth   # open in Cursor
sn3-auth              # shell alias (after terminal restart)
```

## Templates

Templates live in `configs/workspace-templates/` and define the shared workspace structure.

### Template format

Templates use `{{WTW_*}}` placeholders:

```json
{
  "folders": [
    { "name": "{{WTW_WORKSPACE_NAME}}", "path": "{{WTW_CODE_FOLDER}}" },
    { "path": "../../.gstack" },
    { "path": "../obsidian/SnowObsidian" }
  ],
  "settings": {
    "terminal.integrated.cwd": "${workspaceFolder:{{WTW_WORKSPACE_NAME}}}",
    ...
  }
}
```

| Placeholder | Replaced with |
|-------------|---------------|
| `{{WTW_WORKSPACE_NAME}}` | Workspace name (e.g., `snowmain3_auth`) |
| `{{WTW_CODE_FOLDER}}` | Absolute path to the worktree |

Colors (`workbench.colorCustomizations`, `peacock.color`) are **not** in the template — wtw injects them automatically from the color palette.

### Sharing templates across repos

Multiple repos can share a template for consistent terminal profiles, extra folders, and editor settings:

```powershell
# snowmain2 and snowmain3 share the same workspace structure:
wtw init "sn3,snowmain3" --template ./configs/workspace-templates/snowmain.code-workspace.template
wtw init "sn2,snowmain2" --template ./configs/workspace-templates/snowmain.code-workspace.template

# everix has a different structure:
wtw init "e1,everix" --template ./configs/workspace-templates/everix.code-workspace.template
```

### Syncing after template changes

When you update a template (add a folder, change a setting), re-apply it:

```powershell
wtw sync --all --dry-run    # preview what would change
wtw sync --all              # apply to all repos + worktrees
wtw sync --all --repo sn3   # apply to one repo only
```

### Legacy support

If `--template` points to a real `.code-workspace` file (no `{{WTW_*}}` placeholders), wtw falls back to regex replacement of folder paths and `${workspaceFolder:X}` references.

## List Output

`wtw list` shows all registered repos and their worktrees:

```
Kind  Repo       Aliases                      Branch                         Color    Path                                          Workspace
----  ---------  ---------------------------  -----------------------------  -------  --------------------------------------------  --------------------------------
repo  snowmain3  sn3, snowmain3               NTB-Dashboard-Context-Capture  #2285a6  /Users/sno/Data/snogit/snowmain3              snowmain3.code-workspace
  wt             sn3-auth, snowmain3-auth     auth                           #e05d44  /Users/sno/Data/snogit/snowmain3_auth         snowmain3_auth.code-workspace
repo  snowmain2  sn2, snowmain2               landing-page-post-poc          #869336  /Users/sno/Data/snogit/snowmain2              snowmain2.code-workspace
repo  everix1    e1, evx1, everix1            EVX-6008-uptime-monitor        #215732  /Users/sno/Data/everix/everix1                everix1.code-workspace
```

- **Kind**: `repo` = main repo, `wt` = worktree (indented)
- **Aliases**: what you type in `wtw go` / `wtw cursor` / shell shortcuts
- **Path**: where the code lives on disk

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
~/Data/snogit/
├── snowmain3/               # main repo
├── snowmain3_auth/          # worktree: wtw create auth
├── snowmain3_billing/       # worktree: wtw create billing
├── snowmain2/               # another repo copy
├── snowmain2_hotfix/        # worktree: wtw create hotfix (from sn2)
```

## Workspace Files

Generated in the configured `workspacesDir` (default: `~/Data/code-workspaces/`):

```
~/Data/code-workspaces/
├── snowmain3.code-workspace          # main repo (generated by wtw init)
├── snowmain3_auth.code-workspace     # generated by wtw create auth
├── snowmain3_billing.code-workspace  # generated by wtw create billing
```

Each generated workspace:
- Points to the worktree as the code folder
- Keeps extra folders from template (.gstack, obsidian, etc.)
- Gets a unique Peacock color from the 20-color palette
- Has terminal profiles pointing to the correct `${workspaceFolder:X}`
- Stores `wtw.*` metadata in settings for sync support

## Colors

20-color palette auto-assigned per worktree. Colors are recycled when worktrees are removed. Colors are applied to:
- VS Code/Cursor Peacock color customizations (title bar, activity bar, status bar)
- Superset project sidebar (if installed)
- iTerm2 / Windows Terminal tab colors (via `start-repository-session.ps1`)

## Superset Integration

When [Superset](https://superset.sh) is installed (`~/.superset/local.db` exists), wtw automatically:
- Creates/updates a Superset project on `wtw init` and `wtw create` with matching color
- Removes the Superset project on `wtw remove`

## Profile Integration

`wtw install` adds a loader to your PowerShell profile. On shell startup, `Register-WtwProfile` creates shortcut aliases from the registry:

```powershell
sn3              # same as: wtw go sn3
sn3-auth         # same as: wtw go sn3-auth
snowmain3        # same as: wtw go snowmain3
snowmain3-auth   # same as: wtw go snowmain3-auth
```

New worktrees get aliases after terminal restart. Within the current session, use `wtw <name>` directly.

## Alias Collision Protection

`wtw init` rejects aliases already used by another repo:

```
wtw init "sn3,duplicate"
# Error: Alias 'sn3' is already used by repo 'snowmain3'. Choose different aliases.
```

## Git Hooks in Worktrees

Worktrees share hooks with the main repo (`.git` is a file in worktrees, not a directory). `start-repository-session.ps1` detects this and skips hook installation for worktrees.

## Cross-Platform

Works on macOS, Windows, and Linux with PowerShell 7+. Uses `Join-Path` everywhere, `du -sk` for fast size scanning on Unix (falls back to `Get-ChildItem` on Windows).
