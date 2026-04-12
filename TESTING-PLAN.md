# wtw — Testing & CI Plan

Plan for integration tests and GitHub Actions CI. Not yet implemented.

## Current State

- **60 unit tests** across 8 Pester test files covering utilities (color math, JSONC parsing, alias matching, workspace generation, arg parsing, editor shortcuts)
- **0 integration tests** on public functions (init, create, list, remove, sync, etc.)
- **No CI pipeline**

## Integration Test Strategy

### Test Infrastructure

- **Framework**: Pester v5 (already used for unit tests)
- **Isolation**: Each integration test creates a temp directory (`$TestDrive` or `New-TemporaryFile`) with a fresh git repo, runs the workflow, then cleans up
- **Registry isolation**: Override `$script:WtwRegistryPath`, `$script:WtwColorsPath`, `$script:WtwConfigPath` to point to temp files so tests never touch `~/.wtw/`
- **Git isolation**: `git init` in temp dirs — no real repos involved

### Test Suites to Add

#### 1. `Wtw.Init.Tests.ps1` — Registration workflow
- `wtw init` in a git repo creates config, registry entry, and workspace file
- `wtw init "a,b"` registers both aliases
- `wtw init` with `--template` copies template from another repo
- `wtw init` rejects duplicate aliases
- Re-running `wtw init` preserves existing worktrees
- Running outside a git repo produces an error

#### 2. `Wtw.Create.Tests.ps1` — Worktree creation
- `wtw create task` creates git worktree, workspace file, and registry entry
- Branch name defaults to task name
- `--branch` overrides branch name
- `--no-branch` attaches to existing branch
- Duplicate task name rejected
- Color is auto-assigned and unique within repo
- Workspace file contains correct paths and Peacock colors

#### 3. `Wtw.Remove.Tests.ps1` — Worktree removal
- `wtw remove task` deletes worktree dir, workspace file, and registry entry
- Color is recycled after removal
- `--force` skips confirmation
- Removing a non-existent worktree produces an error
- Removing a main repo target produces an error

#### 4. `Wtw.List.Tests.ps1` — List output
- `wtw list` returns all repos and worktrees
- `wtw list --repo alias` filters to one repo
- `wtw list -d` produces detailed output (spot-check for key strings)
- Output includes correct branch names and colors

#### 5. `Wtw.NameResolution.Tests.ps1` — Resolve-WtwTarget
- Exact alias match returns main repo
- `alias-task` format returns worktree
- Bare task name returns worktree (unique)
- Bare task name errors when ambiguous
- Prefix matching works (`au` matches `auth` if unique)
- Fuzzy matching suggests close alternatives

#### 6. `Wtw.Sync.Tests.ps1` — Template sync
- `wtw sync --all` updates all managed workspaces
- `--dry-run` does not modify files
- Template placeholder replacement works
- Colors are preserved during sync
- `--repo` limits scope

#### 7. `Wtw.Color.Tests.ps1` (extend existing)
- `wtw color task random` picks a maximally contrasting color
- `wtw color task ff0000` sets explicit color
- Color propagates to workspace file
- `--no-sync` skips workspace update

#### 8. `Wtw.Clean.Tests.ps1` — Stale worktree cleanup
- Detects directories in configured stale paths
- `--dry-run` lists but doesn't delete
- Respects interactive selection (mock `Read-Host`)

#### 9. `Wtw.Install.Tests.ps1` — Global installation
- Copies module files to target directory
- `--skip-profile` doesn't touch profile
- Blocks self-install from global copy

### Mocking Strategy

| Dependency | Mock approach |
|-----------|---------------|
| `git` commands | Create real temp git repos — no git mocking needed |
| `Read-Host` | Mock for interactive prompts (`Remove`, `Init` alias prompt) |
| `Write-Host` | Let it run; assert on registry/file state, not output |
| File system | Use `$TestDrive` (Pester's built-in temp dir) |
| `~/.wtw/` | Redirect `$script:` path variables to temp dirs in `BeforeAll` |
| Editors (`code`, `cursor`) | Mock `Get-Command` and `&` operator |

### Priority Order

1. Init + Create + Remove (core lifecycle — catches most regressions)
2. Name resolution (complex logic, most likely to break)
3. Sync (template system is critical for correctness)
4. List + Color + Clean (lower risk, mostly display)
5. Install (rarely changes)

## GitHub Actions CI

### Workflow: `.github/workflows/test.yml`

```yaml
name: Tests
on:
  push:
    branches: [main]
    paths: ['**.ps1', '**.psm1', '**.psd1', '**.Tests.ps1']
  pull_request:
    paths: ['**.ps1', '**.psm1', '**.psd1', '**.Tests.ps1']

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - name: Install Pester
        shell: pwsh
        run: Install-Module -Name Pester -MinimumVersion 5.0 -Force -Scope CurrentUser

      - name: Run tests
        shell: pwsh
        run: |
          $config = New-PesterConfiguration
          $config.Run.Path = './tests'
          $config.Output.Verbosity = 'Detailed'
          $config.TestResult.Enabled = $true
          $config.TestResult.OutputFormat = 'NUnitXml'
          $config.TestResult.OutputPath = './test-results.xml'
          Invoke-Pester -Configuration $config

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results-${{ matrix.os }}
          path: test-results.xml

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install PSScriptAnalyzer
        shell: pwsh
        run: Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser

      - name: Run PSScriptAnalyzer
        shell: pwsh
        run: |
          $results = Invoke-ScriptAnalyzer -Path . -Recurse -ExcludeRule PSUseShouldProcessForStateChangingFunctions
          $results | Format-Table -AutoSize
          if ($results | Where-Object Severity -eq 'Error') { exit 1 }
```

### What the CI covers

- **3 OS matrix**: Ubuntu, macOS, Windows (wtw claims cross-platform)
- **Pester tests**: All unit + integration tests
- **PSScriptAnalyzer**: Lint for common PowerShell issues
- **Path filtering**: Only runs when .ps1 files change

### Future additions

- Code coverage reporting (Pester has built-in coverage)
- PowerShell Gallery publish on tag push
- Badge in README
