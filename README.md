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

### Update notice

wtw tells you when a newer version is published. It prints a two-line hint once
per shell session:

```text
  wtw 0.2.0 is available (you have 0.1.46).
  Update: wtw install     (or: Update-Module wtw -Scope CurrentUser)
```

The hint reads only `~/.wtw/update-check.json`, so it never waits on the
network; a stale cache is refreshed by a detached background process and used
by the next command. Being offline, having no cache yet, or a read-only `HOME`
are all silent. The hint is skipped when stdout is redirected — which covers CI
and the subcommands whose output the shell wrappers parse — and when
`WTW_NO_UPDATE_NOTICE=1` is set. `Get-WtwUpdateStatus` reports the same
comparison on demand.

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
- ChatGPT Desktop project metadata, if ChatGPT (or legacy Codex) is installed

### 3. Work in it

```powershell
wtw auth                  # cd to worktree + run session script
wtw cursor auth           # open in Cursor (or: wtw cur auth)
wtw code auth             # open in VS Code (or: wtw co auth)
wtw chatgpt auth          # open in ChatGPT Desktop (aliases: cgpt, codex)
wtw droid auth            # open in Factory desktop app (alias: factory)
wtw chatgpt auth --skip-restart  # open without closing ChatGPT if the label needs repair
wtw claudecode auth       # new Claude Code chat rooted at the worktree (or: wtw ccode auth)
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
| `wtw chatgpt [name] [--skip-restart]` | Open in ChatGPT Desktop (aliases: `cgpt`, `codex`) |
| `wtw droid [name]` | Open in Factory desktop app (alias: `factory`) |
| `wtw claude [name]` | Bring the Claude desktop app forward (aliases: `cowork`) |
| `wtw claudecode [name] [--prompt X]` | Start a new Claude Code chat rooted at the worktree (aliases: `ccode`) |
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
| `wtw host [list\|discover\|add\|remove\|sync\|trust\|test]` | Manage remote machines for `--on` |
| `wtw --on <host> <editor> <name>` | Open a worktree that lives on another machine (see [Remote worktrees](#remote-worktrees)) |

## Remote worktrees

When agents work on more than one machine, the worktree you want to look at is
often not on the machine you are sitting at. `--on` opens it over Remote-SSH:
the editor window is local, the files and the extension host are on the remote.

```powershell
wtw host add workstation --alias at --user dev `
    --address workstation.local,192.168.1.10 `
    --identity ~/.ssh/id_ed25519_workstation --platform windows

wtw host trust workstation  # show host-key fingerprints, then accept
wtw host test at            # addresses + ssh config + remote wtw

wtw list --on at            # what does that machine have?
wtw --on at cursor auth     # open its "auth" worktree here, in Cursor
wtw at cursor auth          # same thing — bare host shorthand
wtw --on at go auth         # ssh into that worktree: pwsh, right directory
```

### `go` — a shell in the remote worktree

`wtw go auth` locally means "be in that worktree". With `--on` it means the same
thing over ssh: an interactive pwsh, already in the directory, with your remote
profile loaded. Aliases: `connect`, `conn`, `ssh`.

```powershell
wtw --on at go auth      # a worktree
wtw --on at go           # just the machine, in its home directory
```

The **local** tab is titled and tinted with that worktree's colour from the
remote registry, and both are restored when you exit, including on Ctrl-C.

Give each machine an identity for those titles:

```powershell
wtw host add workstation --emoji 🧊 --label WS
```

Titles then read `{emoji}{label}.{worktree}` — e.g. `🧊WS.🟢 PF037 gamification`,
where the worktree half is its own pretty name from the remote registry, so a
remote tab looks like the local tab for the same worktree with the machine in
front. The label defaults to the shortest alias upper-cased, so this works before
you configure anything; there is no default emoji, because an auto-assigned one
would be noise rather than identity.

Three details that a plain `ssh host` does not give you:

- `-t` forces a TTY; without it pwsh exits immediately.
- The `Set-Location` travels as `-EncodedCommand`, so paths with spaces or quotes
  survive the local shell, ssh's argv joining and cmd.exe on a Windows remote.
- The title is set **again from inside the session**. A Windows remote runs pwsh
  under ConPTY, which clears the screen and emits its own OSC title the moment it
  starts — clobbering whatever the local terminal was told a moment earlier.

A worktree that is registered but no longer on disk is reported in-session rather
than dumping you in the home directory behind a scrolled-off error.

### Tailscale

If your machines are on a tailnet, skip the manual address wrangling:

```powershell
wtw host discover        # shows a plan, asks before writing
wtw host discover --yes  # non-interactive
```

It reads `tailscale status --json` and registers every machine that can actually
host a worktree. Phones and tablets are recognised and skipped — they are real
tailnet members but cannot run pwsh. The **platform is taken from Tailscale**,
which is exactly what `--platform` needs for remote path translation.

An already-known machine is **updated, not duplicated**: its tailnet addresses
are added in front of the ones you already had. Matching is by exact name or
alias, never by prefix — merging into the wrong machine's entry is worse than a
visible duplicate.

```
    skip     laptop            macos    online   this machine
    add      nas       linux    online   new host
             + nas.tailnet-example.ts.net, 100.64.0.11
    skip     iphone181            -        online   iOS cannot host a worktree
    update   workstation          windows  online   add tailnet addresses
             + workstation.tailnet-example.ts.net, 100.64.0.10
```

Tailnet addresses go **first** in the candidate list on purpose: a tailnet name
resolves on the LAN and away from it, so the ssh config stays valid when you
change networks instead of needing a re-sync. LAN names stay behind it as a
fallback for when Tailscale is down.

Tailscale supplies the machine, not the login — new hosts get your current
username unless you pass `--user`. Aliases are not invented for you.

Not every tailnet member is a dev box. `--exclude a,b` is remembered, so a NAS or
a router is declined once rather than on every run.

**ssh names and Tailscale names do not clash** — they compose. `~/.ssh/config`
maps a *pattern* to a HostName; MagicDNS resolves that HostName. The collision to
watch for is *within* ssh config: wtw's `Include` is first, and OpenSSH takes the
first obtained value per keyword, so any other `Host <name>` block further down
keeps parsing but has its HostName/User/IdentityFile overridden by wtw's.
`wtw host test <name>` reports those blocks with file and line, since the
shadowing is otherwise invisible.

### ZeroTier

Supported as an ordinary address, not auto-discovered. The local ZeroTier client
exposes only *your own* managed address and peer *node IDs* — never member names
or their managed IPs — so there is nothing to enumerate without the ZeroTier
Central API and an account token. `wtw host discover` prints your networks and
your address on each, so you can read a peer's IP off ZeroTier Central and:

```powershell
wtw host add winbox --user dev --address 10.147.20.42 --platform windows
```

### Inspecting and changing hosts

`wtw host list` is one line per host — active address, transport, ssh status.
`wtw host show [name]` is the full picture: every candidate with its transport
and whether it is up, which one is in use, and any other `Host` blocks that match.

There is no separate "edit": `wtw host add` on an existing name writes only the
fields you pass.

Each candidate is classified from the address itself — `tailscale` (`*.ts.net`
or `100.64.0.0/10`), `zerotier` (a subnet this machine joined), `mdns`
(`*.local`), `lan` (RFC1918). The first two work anywhere; the last two only on
the same LAN. `--via` picks one, at either level:

```powershell
wtw --on at list --via tailscale        # one command only, nothing written
wtw at cursor auth --via lan            # the editor opens over the LAN too
wtw host add workstation --via lan      # stored default
wtw host add workstation --via any      # back to first-reachable
```

The stored preference **reorders** the candidate list rather than filtering it —
pinning `lan` and then leaving the LAN falls back to the tailnet instead of
stranding the host, and `host show` says when that happened. The per-command form
is strict: asking for a transport the host does not have is an error.

Per-command `--via` works because `host sync` also emits every candidate address
as its own `Host` pattern — same User and IdentityFile, no `HostName` — so both
ssh and the editor's `ssh-remote+<address>` authority can target an address
directly and still use the right credentials.

### Address candidates

`--address` is an **ordered candidate list**. Put a stable name first and a
last-known IP second: on DHCP — or when a machine moves between wifi and a USB
adapter — the address changes but the name does not. `wtw host sync` probes the
candidates and writes whichever answers on the ssh port, so a moved machine is
one command away rather than a config edit.

Both platforms advertise mDNS: macOS always, Windows 10/11 natively. Check the
name with `scutil --get LocalHostName` (macOS) or `hostname` (Windows).

Reaching a machine by a **new name** needs its host key accepted again — ssh
trusts keys per host pattern, and wtw connects with `BatchMode=yes` so it can
never hang on the prompt. `wtw host trust <name>` scans every candidate, prints
the fingerprints, marks any that already match a host you trust (same machine,
different name) and asks before writing to `known_hosts`.

wtw does **not** mirror the remote's registry. It asks the remote's own wtw
where the worktree currently is (`wtw __resolve_json` over ssh), because that is
the only thing that stays correct while agents create and remove worktrees over
there. Nothing is cached, so nothing goes stale.

### What crosses the network

Only reads and editor launches. `open`, the VS Code family editors, `list` and
`info` accept `--on`.

`list --on` delegates to the remote's own `wtw list` rather than reimplementing
it, so every flag behaves exactly as it does locally (`--detailed`, `--wide`,
`--repo`) and the colour swatches survive the trip.

Commands that change the remote's own registry — `create`, `add`, `remove`,
`sync`, `color`, `clean`, `init`, `copy` — are **executed on the remote**. Running
them there is exactly what keeps its registry authoritative:

```powershell
wtw --on box sync --all
wtw --on box create auth
wtw --on box run init "app,my-app" --cwd /srv/repos/my-app
```

`run` is the explicit escape hatch: it forwards any wtw command verbatim.
`--cwd` sets the remote working directory, which repo-scoped commands need — an
ssh command starts in the remote home directory, not in a repo.

One category is refused outright: `t3` / `cmux` / `wmux` / `claudecode` /
`chatgpt` / `ss`. These are ambiguous rather than impossible — "open T3 here
pointing at a remote path" cannot work, while "register that project over there"
is perfectly meaningful — so the intent has to be stated:
`wtw --on box run t3 auth`.

### Setup notes

- **ssh config is mandatory.** The Remote-SSH extension resolves
  `ssh-remote+<host>` through the ssh client, not through wtw. `wtw host add`
  and `wtw host sync` write `~/.ssh/config.d/wtw` and prepend an `Include` to
  `~/.ssh/config`. The Include goes first because OpenSSH takes the first
  obtained value per keyword — appended after a `Host` block it would apply only
  to that block.
- **Each fork needs its own Remote-SSH extension**: VS Code
  `ms-vscode-remote.remote-ssh`, Cursor `anysphere.remote-ssh`, VSCodium
  `jeanp413.open-remote-ssh` (Microsoft's is proprietary and absent from Open
  VSX). wtw probes what is installed and offers to add one.
- **Windows remotes** need `remote.SSH.remotePlatform` pinned or the connection
  fails with an opaque error. wtw writes it into the editor's `settings.json`
  for `--platform windows` hosts, backing the file up first (comments do not
  survive a JSON rewrite).
- **The remote needs pwsh, found without a login shell.** `ssh host <command>`
  runs a non-login, non-interactive shell, so a PATH exported from `~/.zprofile`
  or `~/.bashrc` does not apply — on an Apple-Silicon Mac that hides
  `/opt/homebrew/bin/pwsh` completely. wtw probes the usual install locations;
  `wtw host add <name> --pwsh <path>` covers anything unusual.
- **Both ends want 0.2.0+.** Discovery asks the remote for `__resolve_json`,
  which older versions do not have. An older remote still works — wtw falls back
  to the legacy `__resolve` and prints *"Remote wtw predates --on"* — but you get
  a folder open instead of the `.code-workspace`, so no Peacock colour or
  multi-root layout.
- **Nothing depends on the remote's `wtw` command.** The payload is a
  `pwsh -EncodedCommand` that imports the module and calls `Invoke-Wtw` directly.
  ssh hands its command string to the remote's *default shell* — cmd.exe on
  Windows, where `wtw` is the cmd shim that treats unknown subcommands as `go`
  targets. Base64 also sidesteps every layer of quote reinterpretation between
  the local shell, ssh, cmd.exe and pwsh.

### Flags

| Flag | Meaning |
|------|---------|
| `--print-only` | Print the resolved editor command and exit — no ssh launch |
| `--folder` | Open the directory even when a `.code-workspace` exists remotely |
| `--skip-checks` | Skip the ssh-config / extension / settings preflight |

`wtw host test <name>` probes both halves (ssh resolution and remote wtw
reachability) when something is not working.

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
| `config.json` | Editor preference, workspaces dir, stale paths to scan, remote hosts |
| `registry.json` | Registered repos, aliases, template paths, worktrees |
| `colors.json` | 20-color palette + per-worktree color assignments |
| `module/` | Globally installed module copy |

### Editor preference

`editor` accepts a single name or an ordered chain:

```jsonc
"editor": "cursor"
"editor": ["cursor", "code"]      // first *runnable* one wins
```

The array is a preference order, not "open in all of them". It exists so one
config file survives machines with different editors installed — which is the
normal case once you open worktrees from more than one box.

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
      "sample1": "team"
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

- **ChatGPT Desktop (formerly Codex)** — trusts the worktree path in `~/.codex/config.toml`, keeps
  a minimal `.codex/config.toml` in the worktree when one is missing, and
  pre-seeds the saved sidebar label in
  `~/.codex/.codex-global-state.json` from the same `--name`/pretty name and
  color-circle prefix used by Superset/SourceGit when ChatGPT is not running.
  When ChatGPT is already running, `wtw chatgpt <name>` prompts to close/relaunch it
  around the label write so the app does not overwrite the external state edit.
  It skips that prompt when the saved label already matches; pass
  `--skip-restart` to open without repairing a missing/stale label.
- **Claude Code (Claude for Desktop)** — `wtw claudecode <name>` (alias
  `wtw ccode <name>`) starts a *new* Claude Code chat rooted at the worktree via
  the app's `claude://code/new?folder=<path>` deep link, launching Claude first
  if it is not running. `wtw create` pre-accepts the "Trust this workspace?"
  prompt for the new worktree by setting `hasTrustDialogAccepted` under
  `projects.<path>` in `~/.claude.json` (honours `$env:CLAUDE_CONFIG_DIR`), and
  `wtw remove` drops that project entry again. Both are no-ops when the file
  does not exist. **Note:** pre-trusting means Claude Code may read, write, and
  execute in the worktree without asking first — the same posture wtw already
  takes for Codex's `trust_level = "trusted"`.
  There is no wtw-settable session label: the desktop app titles sessions itself
  (auto-generated from the first message, renameable in the UI) and identifies
  them by folder. `--prompt <text>` pre-fills the new chat's composer without
  submitting it, which is the closest equivalent to the sidebar labels wtw
  writes for ChatGPT/Cursor. Plain `wtw claude <name>` just brings the app forward.
- **Cursor** — registers the generated `.code-workspace` in Cursor's recent
  workspace list (`state.vscdb`) when Cursor and `sqlite3` are present.
  `wtw cursor <name>` refreshes that entry before opening it. Cursor does not
  expose a separate stable label field in this state; it displays the workspace
  from the generated workspace filename/folder name. Colors come from the
  workspace's `workbench.colorCustomizations` and `peacock.color` settings.
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
- **wmux** — `wtw wmux <name>` (alias `wtw wm <name>`) on Windows selects an
  existing same-named [wmux](https://github.com/amirlehmam/wmux) workspace for
  the worktree's path, or creates one via
  `wmux new-workspace --title <pretty> --cwd <path> --shell pwsh` (starting wmux
  if it isn't running). `wtw create` / `wtw add` likewise create the workspace,
  and `wtw remove` closes it. wmux workspaces are live (daemon-backed) rather
  than a static config registry, so there is no on-disk equivalent of
  `cmux.json`. wmux ships without an installer; wtw finds its Node CLI
  (`<install>/resources/cli/wmux.js`) via `$env:WMUX_EXE`, a running wmux
  process, `wmux.exe` on PATH, then common install dirs — set `$env:WMUX_EXE`
  (and `$env:WMUX_NODE` if `node` isn't on PATH) to override. All of this is a
  no-op when wmux / Node are not found.
- **agentctl** — when installed, attaches ignored local AI-agent overlay files
  to the new worktree using the configured profile. Defaults to `team` for
  safety unless a repo/global override selects another profile.

## Colors — readability

Foreground colors for the colored chrome are chosen by **WCAG contrast ratio**,
not by a brightness threshold. Both a softened near-black and a softened
near-white are scored against the workspace color and the better one wins; if
neither reaches 4.5:1 — which happens on mid-tone reds, teals and blues — it
escalates to pure black or white for maximum contrast.

The active tab also gets `tab.activeBorder` in that foreground color, and keeps
its background when the editor loses focus. Fill alone was a weak cue for "which
file am I in", since the tab shares the title bar's hue.

Re-run `wtw sync --all` after upgrading to re-apply the improved colors to
existing workspaces.

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
