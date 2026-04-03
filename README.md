# wtw — Git Worktree + Workspace Manager

PowerShell 7+ module that manages git worktrees together with VS Code/Cursor `.code-workspace` files.

## Install

```powershell
# From inside the repo containing this module:
Import-Module ./devops/worktree-workspace/wtw.psm1 -Force
wtw install
```

This copies the module to `~/.wtw/module/` and adds a loader to your PowerShell profile.
Re-run `wtw install` after pulling updates to refresh the global install.

## Quick Start

```powershell
# Register current repo
cd ~/Data/snogit/snowmain3
wtw init                     # prompts for alias (e.g., "sn3")

# Create a worktree for a task
wtw create auth              # creates snowmain_auth/ + workspace + branch

# Work in it
wtw go auth                  # cd + session init
wtw open auth                # open workspace in editor

# Done with it
wtw remove auth              # removes worktree + workspace + branch

# Free disk from stale AI worktrees
wtw clean --dry-run          # preview what would be removed
wtw clean                    # interactive removal
```

## Commands

| Command | Description |
|---------|-------------|
| `wtw init [alias]` | Register current repo in wtw |
| `wtw create <task> [--branch X] [--open] [--no-branch]` | Create worktree + workspace |
| `wtw list [--repo alias]` | List registered worktrees |
| `wtw go <name>` | Switch to worktree (cd + session init) |
| `wtw open <name> [--editor X]` | Open workspace in editor |
| `wtw remove <task> [--force]` | Remove worktree + workspace |
| `wtw workspace <name> [--main] [--worktree-path X]` | Generate workspace file only |
| `wtw copy <name> [--code-folder X]` | Standalone copy from template |
| `wtw sync [file\|--all] [--dry-run]` | Re-apply template to managed workspaces |
| `wtw clean [--dry-run] [--force]` | Clean stale AI worktrees |
| `wtw install [--skip-profile]` | Install/update globally to `~/.wtw/module/` |

## Name Resolution for `go` / `open`

- `sn3` — repo alias, goes to main repo
- `sn3-auth` — alias + task, goes to worktree
- `auth` — task name (if unambiguous across repos)

## Config

All config lives in `~/.wtw/`:

| File | Purpose |
|------|---------|
| `config.json` | Editor preference, workspaces dir, stale paths |
| `registry.json` | Registered repos, aliases, worktrees |
| `colors.json` | Color palette + per-worktree assignments |
| `module/` | Globally installed module copy |

## Worktree Layout

Worktrees are created as siblings to the main repo:

```
~/Data/snogit/
├── snowmain3/           # main repo
├── snowmain_auth/       # worktree for "auth" task
├── snowmain_billing/    # worktree for "billing" task
```

## Workspace Files

Generated in the configured `workspacesDir` (default: `~/Data/code-workspaces/`):

```
~/Data/code-workspaces/
├── snowmain3.code-workspace           # template (main repo)
├── snowmain_auth.code-workspace       # generated for auth worktree
├── snowmain_billing.code-workspace    # generated for billing worktree
```

Each generated workspace:
- Points to the worktree as the code folder
- Keeps extra folders from template (.gstack, obsidian, etc.)
- Gets a unique Peacock color from the palette
- Updates `${workspaceFolder:X}` references for terminal profiles
- Stores `wtw.*` metadata in settings for sync support

## Colors

20-color palette auto-assigned per worktree. Colors are recycled when worktrees are removed. The palette is designed for dark editor themes.

## Cross-Platform

Works on macOS, Windows, and Linux with PowerShell 7+. Uses `Join-Path` everywhere, `du -sk` for fast size scanning on Unix (falls back to `Get-ChildItem` on Windows).
