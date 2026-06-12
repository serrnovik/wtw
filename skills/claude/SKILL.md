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

# worktree-workspace

This Claude Code skill is a thin wrapper. Do not duplicate the wtw command
reference here.

Read and follow the canonical cross-agent skill:

- `.agents/skills/worktree-workspace/SKILL.md`

For fuller product documentation, command reference, template behavior, and
installation notes, read:

- `devops/worktree-workspace/README.md`

If this wrapper was installed without the cross-agent skill, install both from
the repo root:

```powershell
wtw skill --agent all
```
