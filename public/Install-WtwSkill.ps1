function Install-WtwSkill {
    <#
    .SYNOPSIS
        Install the wtw AI skill into the current repo for AI agent support.
    .DESCRIPTION
        Copies the wtw skill definition into .claude/skills/ and/or .agents/skills/
        in the current repo root so AI coding agents (Claude, Codex, Cursor, Gemini)
        can discover and use wtw commands.
    .PARAMETER Agent
        Which agent skill format to install: "claude", "agents" (cross-agent), or "all" (default).
    .PARAMETER RepoRoot
        Override the target repo root (default: detected from cwd).
    .EXAMPLE
        wtw skill
        Install all AI skills into the current repo.
    .EXAMPLE
        wtw skill --agent claude
        Install only the Claude Code skill.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('all', 'claude', 'agents')]
        [string] $Agent = 'all',

        [string] $RepoRoot
    )

    if (-not $RepoRoot) {
        $RepoRoot = Resolve-WtwRepoRoot
        if (-not $RepoRoot) {
            Write-Error "Not inside a git repository. Run from a repo or use --repo-root."
            return
        }
    }

    # Find the skill source files (shipped with wtw module)
    $moduleRoot = Join-Path $PSScriptRoot '..'
    $moduleRoot = [System.IO.Path]::GetFullPath($moduleRoot)
    $skillsSource = Join-Path $moduleRoot 'skills'

    if (-not (Test-Path $skillsSource)) {
        Write-Error "Skills directory not found at $skillsSource. Is the wtw module installed correctly?"
        return
    }

    Write-Host ''
    Write-Host '  Installing wtw AI skills...' -ForegroundColor Cyan
    Write-Host "  Repo: $RepoRoot" -ForegroundColor DarkGray

    $installed = @()

    # Claude Code skill (.claude/skills/worktree-workspace/SKILL.md)
    if ($Agent -in @('all', 'claude')) {
        $claudeSource = Join-Path $skillsSource 'claude' 'SKILL.md'
        if (Test-Path $claudeSource) {
            $claudeTarget = Join-Path $RepoRoot '.claude' 'skills' 'worktree-workspace'
            if (-not (Test-Path $claudeTarget)) {
                New-Item -Path $claudeTarget -ItemType Directory -Force | Out-Null
            }
            Copy-Item $claudeSource -Destination (Join-Path $claudeTarget 'SKILL.md') -Force
            $installed += 'Claude Code'
            Write-Host "    .claude/skills/worktree-workspace/SKILL.md" -ForegroundColor Green
        }
    }

    # Cross-agent skill (.agents/skills/worktree-workspace/SKILL.md)
    if ($Agent -in @('all', 'agents')) {
        $agentsSource = Join-Path $skillsSource 'agents' 'SKILL.md'
        if (Test-Path $agentsSource) {
            $agentsTarget = Join-Path $RepoRoot '.agents' 'skills' 'worktree-workspace'
            if (-not (Test-Path $agentsTarget)) {
                New-Item -Path $agentsTarget -ItemType Directory -Force | Out-Null
            }
            Copy-Item $agentsSource -Destination (Join-Path $agentsTarget 'SKILL.md') -Force
            $installed += 'Codex/Cursor/Gemini'
            Write-Host "    .agents/skills/worktree-workspace/SKILL.md" -ForegroundColor Green
        }
    }

    if ($installed.Count -gt 0) {
        Write-Host ''
        Write-Host "  Installed for: $($installed -join ', ')" -ForegroundColor Green
        Write-Host "  AI agents can now use 'wtw create', 'wtw go', 'wtw color', etc." -ForegroundColor DarkGray
    } else {
        Write-Host '  No skills installed.' -ForegroundColor Yellow
    }
    Write-Host ''
}
