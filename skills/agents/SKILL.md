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
# Create a worktree + workspace + branch + optional AI-tool project metadata
pwsh -Command "wtw create <task> [--branch X] [--open]"

# Switch to a worktree
pwsh -Command "wtw go <name>"

# List all repos and worktrees
pwsh -Command "wtw list"          # compact table
pwsh -Command "wtw list --wide"   # full columns when debugging alias resolution
pwsh -Command "wtw list -d"       # detailed view with color swatches

# Remove a worktree (git + workspace + registry)
pwsh -Command "wtw remove <task> [--force]"

# Unregister from wtw only (registry + colors; no git/disk) — pairs with init / add
pwsh -Command "wtw unregister <name> [--repo X] [--force]"

# Set workspace color
pwsh -Command "wtw color [name] [hex|random]"

# Register current repo
pwsh -Command "wtw init [aliases] [--template X] [--startup-script X]"

# Open in editor
pwsh -Command "wtw open [name]"
pwsh -Command "wtw cursor [name]"
pwsh -Command "wtw code [name]"
pwsh -Command "wtw chatgpt [name] [--skip-restart]" # aliases: cgpt, codex
pwsh -Command "wtw claudecode [name] [--prompt X]"  # aliases: ccode — new Claude Code chat in the worktree

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
2. Repo/alias prefix (`pr` → `proj` if unique)
3. `alias-task` format (`app-auth` → worktree)
4. Bare task name (`auth` → searches all repos)
5. Task prefix (`au` → `auth` if unique)
6. Substring (`content` → `my-content-engine`)
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

When ChatGPT Desktop (formerly Codex) is installed/present, `wtw create` also trusts the new
worktree in `~/.codex/config.toml` and pre-seeds the saved sidebar label when
ChatGPT is not running. Use `wtw chatgpt <name>` (or `wtw codex <name>`) to open/register the workspace in
ChatGPT Desktop on demand; if ChatGPT is running, it may prompt to close/relaunch so
the label write is not overwritten. It skips the prompt when the saved label
already matches; pass `--skip-restart` to open without repairing a missing/stale
label. `wtw remove` cleans those Codex entries up.

`wtw claudecode <name>` (alias `ccode`) opens a new Claude Code chat rooted at
the worktree via the Claude desktop app's `claude://code/new?folder=<path>` deep
link. `wtw create` pre-accepts the workspace-trust prompt in `~/.claude.json`
(`projects.<path>.hasTrustDialogAccepted`) and `wtw remove` drops that entry.
The chat title is owned by the app (auto-generated, renameable in the UI) —
`--prompt <text>` only pre-fills the composer. `wtw claude <name>` just brings
the Claude app forward.

## Config

All config lives in `~/.wtw/`:

- `config.json` — editor preference, workspaces directory
- `registry.json` — repos, aliases, worktrees, templates
- `colors.json` — palette and per-worktree color assignments

## Templates

When editing `.code-workspace.template` files, agents can use the following placeholders:
- `{{WTW_WORKSPACE_NAME}}`: Workspace name
- `{{WTW_CODE_FOLDER}}`: Absolute path to the worktree
- `{{WTW_ENV_XYZ}}`: Value of the `XYZ` environment variable. If missing, the folder block containing it is automatically omitted.

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
