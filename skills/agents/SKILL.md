---
name: worktree-workspace
description: |
  Manage git worktrees and VS Code/Cursor workspace files via the wtw CLI.
  Use when the user wants to create, switch between, or clean up worktrees,
  or when managing workspace files for multi-branch workflows.
  Triggers: "create worktree", "new branch workspace", "switch worktree",
  "clean worktrees", "stale worktrees", "worktree disk usage",
  "set workspace color", "change color", "random color".
metadata:
  version: 0.1.0
---

# worktree-workspace (wtw)

Git worktree + VS Code/Cursor workspace manager. One command creates a worktree, workspace file, unique color, and shell aliases.

## Requirements

- PowerShell 7+ (`pwsh`)
- The wtw module must be installed: `Import-Module ~/.wtw/module/wtw.psm1`

## Commands

Run all commands via `pwsh -Command`:

```bash
# Create a worktree + workspace + branch
pwsh -Command "wtw create <task> [--branch X] [--open]"

# Switch to a worktree
pwsh -Command "wtw go <name>"

# List all repos and worktrees
pwsh -Command "wtw list"
pwsh -Command "wtw list -d"   # detailed view with color swatches

# Remove a worktree
pwsh -Command "wtw remove <task> [--force]"

# Set workspace color
pwsh -Command "wtw color [name] [hex|random]"

# Register current repo
pwsh -Command "wtw init [aliases] [--template X] [--startup-script X]"

# Open in editor
pwsh -Command "wtw open [name]"
pwsh -Command "wtw cursor [name]"
pwsh -Command "wtw code [name]"

# Clean stale AI worktrees
pwsh -Command "wtw clean [--dry-run]"

# Sync templates
pwsh -Command "wtw sync --all [--dry-run]"

# Install globally
pwsh -Command "wtw install"
```

## Name Resolution

wtw resolves names flexibly:
1. Exact repo alias (`app` → main repo)
2. Repo/alias prefix (`sn` → `sn3` if unique)
3. `alias-task` format (`app-auth` → worktree)
4. Bare task name (`auth` → searches all repos)
5. Task prefix (`au` → `auth` if unique)
6. Substring (`content` → `ntb-content-engine`)
7. Fuzzy match (Levenshtein distance)

## Color Management

```bash
# Show current color
pwsh -Command "wtw color"

# Set a specific color (hex, without #)
pwsh -Command "wtw color auth e05d44"

# Random color with maximum contrast
pwsh -Command "wtw color auth random"
```

Colors from a 20-color palette are auto-assigned on `wtw create`. They apply to:
- VS Code/Cursor Peacock extension (title bar, activity bar, status bar)
- Terminal tabs (iTerm2, Windows Terminal, Kitty, Konsole, tmux)

## Config

All config lives in `~/.wtw/`:
- `config.json` — editor preference, workspaces directory
- `registry.json` — repos, aliases, worktrees, templates
- `colors.json` — palette and per-worktree color assignments

## Safety Rules

- NEVER run `wtw clean` without `--dry-run` first
- NEVER run `wtw remove` without confirmation unless `--force` is explicit
- Prefer `wtw create` over manual `git worktree add`
- Do not edit `~/.wtw/registry.json` directly — use wtw commands

## Common Workflows

### Start a new feature
```bash
pwsh -Command "wtw create auth --open"
```

### Switch between tasks
```bash
pwsh -Command "wtw go auth"
```

### Change workspace color
```bash
pwsh -Command "wtw color auth random"
```

### Reclaim disk from AI tools
```bash
pwsh -Command "wtw clean --dry-run"
```
