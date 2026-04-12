---
name: worktree-workspace
description: |
  Manage git worktrees and VS Code/Cursor workspace files via the wtw CLI.
  Use when the user wants to create, switch between, or clean up worktrees,
  or when managing workspace files for multi-branch workflows.
  Triggers: "create worktree", "new branch workspace", "switch worktree",
  "clean worktrees", "stale worktrees", "worktree disk usage",
  "set workspace color", "change color", "random color".
allowed-tools:
  - Bash
  - Read
---

# worktree-workspace Skill

You have access to `wtw`, a PowerShell CLI for managing git worktrees + VS Code/Cursor workspace files.

## When to Use

- User wants to work on a new branch/feature in isolation
- User wants to switch between worktrees
- User asks about stale/orphaned worktrees or disk usage
- User wants to generate or update workspace files
- User mentions worktree cleanup or AI worktree bloat
- User wants to change a workspace color or generate a random one
- User wants to see registered worktrees with details

## Key Commands

```powershell
wtw init [alias] [--template X] [--startup-script X]  # Register current repo
wtw create <task> [--branch X] [--open]                # Create worktree + workspace + branch
wtw go <name>                                          # Switch to worktree (cd + session init)
wtw <name>                                             # Same as go (implicit)
wtw open <name>                                        # Open workspace in editor
wtw list                                               # Show all repos and worktrees (table)
wtw list -d                                            # Detailed view with color swatches + settings links
wtw remove <task> [--force]                            # Remove worktree + workspace
wtw color [name] [hex|random]                          # Set or show workspace color
wtw clean [--dry-run]                                  # Interactive cleanup of stale AI worktrees
wtw workspace <name> [--main]                          # Generate workspace file without git worktree
wtw sync --all [--dry-run]                             # Re-apply template updates to managed workspaces
wtw install                                            # Install/update globally (~/.wtw/module/)
```

## Editor shortcuts

```powershell
wtw cursor <name>       # Open in Cursor (alias: cur)
wtw code <name>         # Open in VS Code (alias: co)
wtw antigravity <name>  # Open in Antigravity (alias: anti, ag)
wtw windsurf <name>     # Open in Windsurf (alias: wind, ws)
wtw codium <name>       # Open in VSCodium (alias: vscodium)
```

## Color management

```powershell
wtw color                        # Show current workspace color
wtw color auth random            # Pick a maximally contrasting random color
wtw color auth e05d44            # Set specific hex color (omit # or quote it)
wtw color auth --no-sync         # Set color without updating workspace file
```

Colors are auto-assigned from a 20-color palette. `random` picks the color with maximum perceptual distance from all others in the repo. Colors apply to:
- VS Code/Cursor Peacock (title bar, activity bar, status bar)
- iTerm2 / Windows Terminal / Kitty / tmux tab colors

## Name resolution

wtw resolves names in this order:
1. Exact repo alias (`sn3` → main repo)
2. Repo/alias prefix (`sn` → `sn3` if unique)
3. `alias-task` format (`sn3-auth` → worktree)
4. Bare task name (`auth` → searches all repos)
5. Task prefix (`au` → `auth` if unique)
6. **Substring** (`content` → `ntb-content-engine`)
7. Fuzzy match (Levenshtein distance)

## Important Patterns

### One active code folder per workspace
Each generated workspace has exactly one code folder (the worktree) plus stable context folders. Do NOT add multiple worktrees to a single workspace.

### Worktree naming
Worktrees are siblings to the main repo: `{repoBaseName}_{task}`

### Config location
All config in `~/.wtw/`: `config.json`, `registry.json`, `colors.json`

## Safety Rules

- NEVER run `wtw clean` without `--dry-run` first unless the user explicitly asks
- NEVER run `wtw remove` without confirmation unless the user says `--force`
- Prefer `wtw create` over manual `git worktree add` — it handles workspace + color + registry
- When suggesting cleanup, always show the `--dry-run` output first
- Do not modify `~/.wtw/registry.json` directly — use wtw commands

## Common Workflows

### Start a new feature
```powershell
wtw create auth --open     # creates worktree, workspace, opens in editor
```

### Switch between tasks
```powershell
wtw go auth                # or just: wtw auth
```

### Change workspace color
```powershell
wtw color auth random      # max-contrast auto-pick
```

### After template changes
```powershell
wtw sync --all --dry-run   # preview
wtw sync --all             # apply
```

### Reclaim disk from AI tools
```powershell
wtw clean --dry-run        # see what's stale
wtw clean                  # interactive selection
```

## Dev Environment Variables

When switching to a worktree, wtw exports environment variables that build/deploy tools can use for isolation:

| Variable | In worktree | In main repo |
|----------|------------|-------------|
| `DEV_WORKTREE_ID` | `auth` | *(empty)* |
| `DEV_WORKTREE_DASHED_POSTFIX` | `-auth` | *(empty)* |
| `DEV_WORKTREE_PORT_OFFSET` | `100` | `0` |
| `DEV_WORKTREE_INDEX` | `1` | `0` |

These are generic (tool-agnostic). Use them in jaxfiles or deploy scripts:
```yaml
# Namespace with optional worktree suffix
namespace: "{{ boss.suite.name }}{{ env.DEV_WORKTREE_DASHED_POSTFIX }}"
```
