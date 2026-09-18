

function Invoke-Wtw {
    <#
    .SYNOPSIS
        Main CLI dispatcher for wtw.
    .DESCRIPTION
        Routes subcommands (create, list, sync, clean, etc.) to their handler
        functions. Parses raw CLI arguments via Convert-WtwArgsToSplat and splats
        them to the target command. Does not use [CmdletBinding()] because it
        relies on automatic $args for flexible dispatch.
    .EXAMPLE
        wtw create auth --open
        Creates a worktree and workspace for "auth" and opens it in the editor.
    .EXAMPLE
        wtw sync --all --dry-run
        Preview-syncs all managed workspaces.
    #>
    $Command = $null
    $rawArgs = @()

    # Host selector first: dispatch below keys off $args[0], so a leading
    # `--on <host>` would otherwise be mistaken for the subcommand.
    #
    # The host list is only read when it can matter. The `__*` commands are
    # called by the zsh/bash integration on every directory change and never
    # take --on, so they skip the extra config parse entirely.
    $onHosts = @()
    if ($args.Count -gt 0 -and "$($args[0])" -notlike '__*') {
        try { $onHosts = Get-WtwHostNames } catch { $onHosts = @() }
    }
    $split = Split-WtwOnHostArgs -ArgList $args -KnownHosts $onHosts
    $targetHost = $split.Host
    $effectiveArgs = @($split.Args)

    if ($effectiveArgs.Count -gt 0) {
        $Command = $effectiveArgs[0]
    }
    if ($effectiveArgs.Count -gt 1) {
        $rawArgs = $effectiveArgs[1..($effectiveArgs.Count - 1)]
    }

    # Newer-version hint. Emitted up front because the dispatch below returns
    # from many branches. Cache-only, silent on failure, and skipped for the
    # internal `__*` commands whose stdout the shell wrappers parse.
    if ([string]$Command -notlike '__*' -and $Command -notin @('--version', '-v', 'version')) {
        Write-WtwUpdateNotice
    }

    if ($Command -in @('--version', '-v', 'version')) {
        Show-WtwVersion
        return
    }

    # `wtw --on at` with no subcommand: open the remote machine as a cmux
    # project (or ssh into home when cmux is not installed). `wtw at` alone
    # stays a local go target — shorthand requires a following command.
    if ($targetHost -and -not $Command) {
        $hostEntry = Resolve-WtwHost -Name $targetHost
        if (-not $hostEntry) {
            if (Test-WtwIsLocalMachine -Name $targetHost) {
                Write-Error "'$targetHost' is this machine — --on names the machine you want to reach."
                return
            }
            $localNames = Get-WtwLocalMachineName
            $whoAmI = if ($localNames.Count -gt 0) { " This machine is '$($localNames[0])'; hosts are the other machines you connect to." } else { '' }
            Write-Error "Unknown host '$targetHost'. Configured hosts: $((Get-WtwHostNames) -join ', ').$whoAmI Add one with: wtw host add $targetHost --user <u> --address <ip>"
            return
        }

        if (Test-WtwCmuxPresent) {
            Open-WtwCmuxRemoteWorkspace -HostEntry $hostEntry -HostSelector $targetHost
        } else {
            Connect-WtwRemoteWorktree -HostEntry $hostEntry -Name ''
        }
        return
    }

    if (-not $Command) {
        Write-WtwHost ''
        Write-WtwHost '  wtw - Git Worktree + Workspace Manager' -ForegroundColor Cyan
        Write-WtwHost ''
        Write-WtwHost '  Commands:' -ForegroundColor Yellow
        Write-WtwHost '    init [aliases]    Initialise current repo as a main repo (--template, --startup-script, --emoji)'
        Write-WtwHost '    add [path]        Adopt an existing on-disk worktree with full registration (workspace + color + cmux/SourceGit/etc.)'
        Write-WtwHost '    create <task>     Create worktree + branch (--emoji for identity glyph; --branch / --adopt to attach an existing branch)'
        Write-WtwHost '    list [repo] [-f|--filter <text>] [-d|--detailed] [--wide]  List repos/worktrees'
        Write-WtwHost '    info <name>       Show full details for a repo or worktree  (alias: show)'
        Write-WtwHost '    go <name>         Switch to worktree (cd + session init)'
        Write-WtwHost '    open [name]       Open workspace in editor (default: current)'
        Write-WtwHost '    cursor [name]     Open in Cursor      (alias: cur)'
        Write-WtwHost '    code [name]       Open in VS Code     (alias: co)'
        Write-WtwHost '    antigravity [name] Open in Antigravity (alias: anti)'
        Write-WtwHost '    windsurf [name]   Open in Windsurf    (alias: wind, ws)'
        Write-WtwHost '    codium [name]     Open in VSCodium    (alias: vscodium)'
        Write-WtwHost '    chatgpt [name] [--skip-restart]  Open in ChatGPT (aliases: cgpt, codex)'
        Write-WtwHost '    droid [name]     Open in Factory desktop app (alias: factory)'
        Write-WtwHost '    cmux [name]       Open in cmux terminal workspace (alias: cm)'
        Write-WtwHost '    wmux [name]       Open in wmux terminal workspace (alias: wm)'
        Write-WtwHost '    claude [name]     Open Claude.ai app  (alias: cowork)'
        Write-WtwHost '    claudecode [name] [--prompt <text>]  New Claude Code chat in the worktree (alias: ccode)'
        Write-WtwHost '    t3 [name]         Add + open T3 Code project  (alias: t3code)'
        Write-WtwHost '    ss [name]         Find & open matching Superset workspace (alias: superset, supersetsh)'
        Write-WtwHost '    remove <task>     Remove worktree + workspace  (alias: rm, delete, del)'
        Write-WtwHost '    unregister <name> Drop repo or worktree from wtw registry only (alias: unreg)'
        Write-WtwHost '    edit [name]       Edit registry record: --name / --task / --alias / --key / --emoji / --sourcegit-folder  (alias: rename, ren)'
        Write-WtwHost '    workspace <name>  Generate workspace file only (no git worktree)'
        Write-WtwHost '    copy <name>       Standalone copy of workspace from template'
        Write-WtwHost '    color [name] [hex|random]   Set workspace color (--no-sync to skip sync)'
        Write-WtwHost '    sync [file|--all] Re-apply template to managed workspaces'
        Write-WtwHost '    clean             Clean stale worktrees and/or merged local branches'
        Write-WtwHost '    agent profile ... Configure agentctl profile overlays'
        Write-WtwHost '    install           Install wtw globally from this checkout (~/.wtw/module/)'
        Write-WtwHost '    update [--check]  Update the global install to the latest PowerShell Gallery release'
        Write-WtwHost '    skill [--agent X] Install AI skill into current repo (claude/agents/all)'
        Write-WtwHost '    sbx [task] [--name <n>] [--agent <a>] [--writable] [--dry-run]'
        Write-WtwHost '                      Launch AI sandbox (sbx) with workspace folders mounted'
        Write-WtwHost '    host [list|self|add|remove|sync|test]  Manage remote machines for --on'
        Write-WtwHost '    self [--emoji X] [--label X]  This machine''s cmux group badge (🍏SP)'
        Write-WtwHost '    version           Print the installed module version'
        Write-WtwHost ''
        Write-WtwHost '  Options:' -ForegroundColor Yellow
        Write-WtwHost '    --help, -h        Show this help'
        Write-WtwHost '    --version, -v     Print the installed module version (alias: wtw version)'
        Write-WtwHost '    --on <host>       Open a worktree that lives on another machine over Remote-SSH.'
        Write-WtwHost '    --at <host>       Alias of --on.'
        Write-WtwHost '                      Shorthand: wtw <host> <editor> <name>'
        Write-WtwHost '                      Works with open/cursor/code/antigravity/windsurf/codium,'
        Write-WtwHost '                      list/info, go, and cmux.'
        Write-WtwHost '                      Extra flags: --print-only, --folder, --skip-checks'
        Write-WtwHost '    --via <transport> One-off: force this command over tailscale|zerotier|'
        Write-WtwHost '                      mdns|lan. Changes nothing on disk.'
        Write-WtwHost '    run <cmd> [--cwd <remote path>]   With --on: run any wtw command ON the'
        Write-WtwHost '                      remote (create/init/sync/... already route there).'
        Write-WtwHost '    go <name>         With --on: ssh into that worktree — pwsh in the right'
        Write-WtwHost '                      directory, local tab titled and coloured. (aliases:'
        Write-WtwHost '                      connect, conn, ssh)'
        Write-WtwHost '    cmux [name]       With --on: local cmux workspace whose terminal is that'
        Write-WtwHost '                      same ssh session (alias: cm). Name omitted → remote home.'
        Write-WtwHost '    (no command)      With --on: open the machine as a cmux project (ssh home'
        Write-WtwHost '                      if cmux is missing). Same as `wtw --on <host> cmux`.'
        Write-WtwHost ''
        return
    }

    # ---- Remote (--on <host>) -------------------------------------------------
    # Only reads and editor launches cross the network: the remote wtw owns its
    # own registry, so anything that mutates it must run over there.
    if ($targetHost) {
        $hostEntry = Resolve-WtwHost -Name $targetHost
        if (-not $hostEntry) {
            # The direction mix-up: `--on` names the OTHER machine, and the same
            # aliases usually exist on both sides, so pointing it at this one is
            # easy to do and reads as a bare "unknown host" without this.
            if (Test-WtwIsLocalMachine -Name $targetHost) {
                Write-Error "'$targetHost' is this machine — --on names the machine you want to reach. Drop it: wtw $Command $($rawArgs -join ' ')"
                return
            }
            # No @() wrapper: the function returns `,@(...)` already, and
            # re-wrapping nests it so [0] is the whole array.
            $localNames = Get-WtwLocalMachineName
            $whoAmI = if ($localNames.Count -gt 0) { " This machine is '$($localNames[0])'; hosts are the other machines you connect to." } else { '' }
            Write-Error "Unknown host '$targetHost'. Configured hosts: $((Get-WtwHostNames) -join ', ').$whoAmI Add one with: wtw host add $targetHost --user <u> --address <ip>"
            return
        }
        $remoteMode = Get-WtwRemoteCommandMode -Command $Command
        if ($remoteMode -eq 'none') {
            Write-Error "'$Command' cannot run with --on — there is no local meaning for it and no unambiguous remote one. To run it on $($hostEntry.Name) verbatim: wtw --on $($hostEntry.Name) run $Command ..."
            return
        }

        $remoteParsed = Convert-WtwArgsToSplat $rawArgs
        $remoteSplat = $remoteParsed.Splat
        $remotePos = $remoteParsed.Positional

        # Per-invocation transport override. Unlike `wtw host add --via`, this
        # changes nothing on disk — it retargets this one command at a specific
        # address, which also becomes the editor's ssh-remote authority.
        $requestedVia = $null
        if ($remoteSplat.Contains('Via')) {
            $requestedVia = [string]$remoteSplat['Via']
            $retargeted = Resolve-WtwHostVia -HostEntry $hostEntry -Via $requestedVia
            if (-not $retargeted) {
                $kinds = @(@($hostEntry.HostNames) | ForEach-Object { Get-WtwAddressKind -Address $_ }) | Select-Object -Unique
                Write-Error "'$($hostEntry.Name)' has no '$requestedVia' address. It has: $($kinds -join ', '). Add one with: wtw host add $($hostEntry.Name) --address <addr>"
                return
            }
            $hostEntry = $retargeted
            Write-WtwHost "  via $requestedVia → $($hostEntry.Name)" -ForegroundColor DarkGray
            # Consumed locally — the remote CLI has no --via.
            $rawArgs = Remove-WtwFlagWithValue -ArgList $rawArgs -Flag 'via'
        }

        # Interactive ssh into the worktree — the remote sibling of `wtw go`.
        if ($remoteMode -eq 'connect') {
            $connectName = if ($remotePos.Count -gt 0) { Join-WtwTargetName $remotePos } else { '' }
            Connect-WtwRemoteWorktree `
                -HostEntry $hostEntry `
                -Name $connectName `
                -PrintOnly:([bool]$remoteSplat.Contains('PrintOnly'))
            return
        }

        # Local cmux workspace whose terminal is that same ssh session.
        if ($remoteMode -eq 'cmux') {
            $connectName = if ($remotePos.Count -gt 0) { Join-WtwTargetName $remotePos } else { '' }
            Open-WtwCmuxRemoteWorkspace `
                -HostEntry $hostEntry `
                -HostSelector $targetHost `
                -Name $connectName `
                -Via $requestedVia `
                -PrintOnly:([bool]$remoteSplat.Contains('PrintOnly'))
            return
        }

        # Forwarded verbatim and executed on the remote. `run` drops its own name
        # so `wtw --on at run create x` becomes `create x` over there.
        if ($remoteMode -eq 'exec') {
            $remoteCwd = if ($remoteSplat.Contains('Cwd')) { [string]$remoteSplat['Cwd'] } else { $null }
            $execArgs = [string[]]@($rawArgs | ForEach-Object { "$_" })
            if ($remoteCwd) { $execArgs = Remove-WtwFlagWithValue -ArgList $execArgs -Flag 'cwd' }
            if ($Command -ne 'run') { $execArgs = @($Command) + @($execArgs) }

            if (@($execArgs).Count -eq 0) {
                Write-Error "Usage: wtw --on $($hostEntry.Name) run <wtw command> [--cwd <remote path>]"
                return
            }

            $where = if ($remoteCwd) { " in $remoteCwd" } else { '' }
            Invoke-WtwRemoteWtw -HostEntry $hostEntry -Arguments $execArgs -WorkingDirectory $remoteCwd `
                -Title "wtw $($execArgs -join ' ')  on $($hostEntry.Name)$where"
            return
        }

        if ($Command -in @('list', 'ls')) {
            # Forward the flags verbatim — the remote's own CLI parses them, so
            # --detailed / --wide / --repo behave exactly as they do locally.
            Get-WtwRemoteList -HostEntry $hostEntry -Arguments ([string[]]@($rawArgs | ForEach-Object { "$_" }))
            return
        }
        if ($Command -in @('info', 'show')) {
            $target = if ($remotePos.Count -gt 0) { Join-WtwTargetName $remotePos } else { $null }
            if (-not $target) { Write-Error "Usage: wtw info <name> --on $($hostEntry.Name)"; return }
            $remote = Get-WtwRemoteTarget -HostEntry $hostEntry -Name $target
            if (-not $remote) { Write-Error "'$target' did not resolve on $($hostEntry.Name)."; return }
            Write-WtwHost ''
            Write-WtwHost "  $($remote.Title ?? $target)  on $($hostEntry.Name)" -ForegroundColor Cyan
            Write-WtwHost "    path       $($remote.Path)"
            if ($remote.Workspace) { Write-WtwHost "    workspace  $($remote.Workspace)" }
            if ($remote.Color)     { Write-WtwHost "    color      $($remote.Color)" }
            Write-WtwHost "    uri        $(ConvertTo-WtwRemoteUri -Path $remote.Path -HostName $hostEntry.Name -Platform $hostEntry.Platform)" -ForegroundColor DarkGray
            Write-WtwHost ''
            return
        }

        # open / <editor> [name]
        $editorName = if ($Command -eq 'open') {
            $config = Get-WtwConfig
            $preference = if ($config) { Get-WtwPropertyValue -Object $config -Name 'editor' -DefaultValue 'code' } else { 'code' }
            $resolved = Resolve-WtwEditorPreference -Editor $preference -Require { param($name) [bool](Resolve-WtwEditorFamilyMember -Name $name) }
            if ($resolved -is [string]) { $resolved } else { $null }
        } else {
            $member = Resolve-WtwEditorFamilyMember -Name $Command
            if ($member) { $member.Id } else { $null }
        }

        if (-not $editorName) {
            Write-Error "No VS Code family editor available for a remote open. Set one: wtw open --editor cursor --on $($hostEntry.Name)"
            return
        }

        $name = if ($remotePos.Count -gt 0) { Join-WtwTargetName $remotePos } else { $null }
        if (-not $name) {
            Write-Error "A remote open needs an explicit target name — the local cwd says nothing about $($hostEntry.Name). Try: wtw list --on $($hostEntry.Name)"
            return
        }

        Open-WtwRemoteWorkspace `
            -HostEntry $hostEntry `
            -Name $name `
            -Editor $editorName `
            -Folder:([bool]$remoteSplat.Contains('Folder')) `
            -PrintOnly:([bool]$remoteSplat.Contains('PrintOnly')) `
            -SkipChecks:([bool]$remoteSplat.Contains('SkipChecks'))
        return
    }

    $parsed = Convert-WtwArgsToSplat $rawArgs
    $splat = $parsed.Splat
    $pos = $parsed.Positional

    # --help / -h / help on any subcommand → show command-specific help
    if ($splat.Contains('Help') -or $splat.Contains('h') -or $pos -contains 'help') {
        Show-WtwCommandHelp $Command
        return
    }

    # Merge positional args into splat at position keys for commands that take them
    # Most commands take a single positional arg (task/name)
    # We handle this by manually adding positional params
    switch ($Command) {
        'init'    { if ($pos.Count -gt 0) { $splat['Alias'] = $pos[0] }; Initialize-WtwConfig @splat }
        'add'     {
            if ($splat.Contains('Emoji') -and $splat['Emoji'] -is [System.Management.Automation.SwitchParameter]) {
                Write-Error '--emoji requires a value.'
                return
            }
            if ($pos.Count -gt 0) { $splat['Path'] = $pos[0] }
            # Match `wtw create --name <pretty>` ergonomics — splat-key 'Name'
            # → PrettyName param so the same user-facing flag works here.
            if ($splat.Contains('Name')) {
                $splat['PrettyName'] = $splat['Name']
                $splat.Remove('Name')
            }
            Add-WtwEntry @splat
        }
        'create'  {
            if ($splat.Contains('Emoji') -and $splat['Emoji'] -is [System.Management.Automation.SwitchParameter]) {
                Write-Error '--emoji requires a value.'
                return
            }
            if ($pos.Count -gt 0) {
                $splat['Task'] = if ($pos.Count -eq 1) { $pos[0] } else { $pos -join ' ' }
            }
            # --name <pretty> → PrettyName param (avoids clash with positional Name resolution).
            # `$splat` is an ordered dictionary (`[ordered] @{ ... }`), which exposes
            # `Contains()` rather than `ContainsKey()` — calling the latter would throw
            # at runtime the moment `wtw create --name <pretty>` is invoked.
            if ($splat.Contains('Name')) {
                $splat['PrettyName'] = $splat['Name']
                $splat.Remove('Name')
            }
            New-WtwWorktree @splat
        }
        'list'    {
            if ($splat.Contains('f') -and $splat['f'] -is [System.Management.Automation.SwitchParameter]) {
                Write-Error '-f / --filter needs a value. Example: wtw list -f kul'
                return
            }
            if ($splat.Contains('Filter') -and $splat['Filter'] -is [System.Management.Automation.SwitchParameter]) {
                Write-Error '-f / --filter needs a value. Example: wtw list -f kul'
                return
            }
            if ($pos.Count -gt 0) { $splat['Repo'] = $pos[0] }
            Get-WtwList @splat
        }
        'ls'      {
            if ($splat.Contains('f') -and $splat['f'] -is [System.Management.Automation.SwitchParameter]) {
                Write-Error '-f / --filter needs a value. Example: wtw list -f kul'
                return
            }
            if ($splat.Contains('Filter') -and $splat['Filter'] -is [System.Management.Automation.SwitchParameter]) {
                Write-Error '-f / --filter needs a value. Example: wtw list -f kul'
                return
            }
            if ($pos.Count -gt 0) { $splat['Repo'] = $pos[0] }
            Get-WtwList @splat
        }
        'info'    { if ($pos.Count -gt 0) { $splat['Name'] = Join-WtwTargetName $pos }; Show-WtwInfo @splat }
        'show'    { if ($pos.Count -gt 0) { $splat['Name'] = Join-WtwTargetName $pos }; Show-WtwInfo @splat }
        'go'      { if ($pos.Count -gt 0) { $splat['Name'] = Join-WtwTargetName $pos }; Enter-WtwWorktree @splat }
        'open'    { if ($pos.Count -gt 0) { $splat['Name'] = Join-WtwTargetName $pos }; Open-WtwWorkspace @splat }
        'remove'  { if ($pos.Count -gt 0) { $splat['Name'] = Join-WtwTargetName $pos }; Remove-WtwWorktree @splat }
        'rm'      { if ($pos.Count -gt 0) { $splat['Name'] = Join-WtwTargetName $pos }; Remove-WtwWorktree @splat }
        'delete'  { if ($pos.Count -gt 0) { $splat['Name'] = Join-WtwTargetName $pos }; Remove-WtwWorktree @splat }
        'del'     { if ($pos.Count -gt 0) { $splat['Name'] = Join-WtwTargetName $pos }; Remove-WtwWorktree @splat }
        'unregister' { if ($pos.Count -gt 0) { $splat['Name'] = Join-WtwTargetName $pos }; Unregister-WtwEntry @splat }
        'unreg'   { if ($pos.Count -gt 0) { $splat['Name'] = Join-WtwTargetName $pos }; Unregister-WtwEntry @splat }
        { $_ -in 'edit', 'rename', 'ren' } {
            # `--name` is the pretty/alias edit (same flag as create). The
            # target is the first positional, or cwd when omitted. A lone
            # `--name` with no target is therefore the new display name.
            if ($splat.Contains('Name') -and $splat['Name'] -is [System.Management.Automation.SwitchParameter]) {
                Write-Error '--name requires a value.'
                return
            }
            if ($splat.Contains('Emoji') -and $splat['Emoji'] -is [System.Management.Automation.SwitchParameter]) {
                Write-Error '--emoji requires a value.'
                return
            }
            if ($pos.Count -gt 0) {
                if ($splat.Contains('Name')) {
                    $splat['PrettyName'] = $splat['Name']
                }
                $splat['Name'] = $pos[0]
            } elseif ($splat.Contains('Name')) {
                $splat['PrettyName'] = $splat['Name']
                $splat.Remove('Name')
            }
            if ($pos.Count -gt 1 -and -not $splat.Contains('PrettyName')) {
                $splat['PrettyName'] = $pos[1]
            }
            Edit-WtwEntry @splat
        }
        'workspace' { if ($pos.Count -gt 0) { $splat['Name'] = Join-WtwTargetName $pos }; New-WtwWorkspace @splat }
        'ws'        { if ($pos.Count -gt 0) { $splat['Name'] = Join-WtwTargetName $pos }; New-WtwWorkspace @splat }
        'copy'      { if ($pos.Count -gt 0) { $splat['Name'] = Join-WtwTargetName $pos }; Copy-WtwWorkspace @splat }
        'sync'      { if ($pos.Count -gt 0) { $splat['Target'] = $pos[0] }; Sync-WtwWorkspace @splat }
        'color'     { 
            $resolved = Resolve-WtwColorArgs $pos
            foreach ($k in $resolved.Keys) { $splat[$k] = $resolved[$k] }
            Set-WtwColor @splat 
        }
        'clean'     { Invoke-WtwClean @splat }
        'host'      {
            if ($pos.Count -gt 0) { $splat['Action'] = $pos[0] }
            if ($pos.Count -gt 1) { $splat['Name'] = $pos[1] }
            Invoke-WtwHost @splat
        }
        'self'      {
            $splat['Action'] = 'self'
            Invoke-WtwHost @splat
        }
        'agent'     { Invoke-WtwAgent @rawArgs }
        'install'   { Install-Wtw @splat }
        # `update` is no longer an alias of `install`. Install copies a checkout
        # into ~/.wtw/module; update replaces whatever is there with the Gallery
        # release. Aliasing them meant `wtw update` from a normal shell hit
        # Install-Wtw's self-install guard and refused to do anything.
        'update'    { Update-Wtw @splat }
        'reload'    { Invoke-WtwReloadSession @splat }
        'skill'     { Install-WtwSkill @splat }
        'sbx'       {
            if ($pos.Count -gt 0) { $splat['Instruction'] = $pos -join ' ' }
            Invoke-WtwSbx @splat
        }
        'help'    { Invoke-Wtw }
        # Internal commands for shell integration (zsh/bash wrappers call these)
        '__commands' {
            # One name per line. Wrappers use this so zsh/bash/cmd cannot drift
            # from the PowerShell CLI when deciding passthrough vs implicit go.
            Get-WtwCliCommandNames | ForEach-Object { Write-Output $_ }
        }
        '__hosts' {
            try { Get-WtwHostNames | ForEach-Object { Write-Output $_ } } catch { }
        }
        '__shell_state' {
            $shellType = $splat['Shell'] ?? ''
            Write-Output '#wtw-commands'
            Get-WtwCliCommandNames | ForEach-Object { Write-Output $_ }
            Write-Output '#wtw-hosts'
            try { Get-WtwHostNames | ForEach-Object { Write-Output $_ } } catch { }
            Write-Output '#wtw-aliases'
            if ($shellType) {
                Invoke-Wtw '__aliases' '--shell' $shellType
            } else {
                Invoke-Wtw '__aliases'
            }
        }
        '__resolve_path' {
            # Output: just the absolute path to the target (single line, no
            # tabs). Used by wtw.cmd so cmd.exe can `cd /d` to it cleanly
            # without parsing tab-delimited fields.
            if ($pos.Count -eq 0) { Write-Error "Usage: wtw __resolve_path <name>"; return }
            $target = & { Resolve-WtwTarget (Join-WtwTargetName $pos) } 6>$null
            if (-not $target) { exit 1 }
            $p = if ($target.WorktreeEntry) { $target.WorktreeEntry.path } else { $target.RepoEntry.mainPath }
            Write-Output $p
        }
        '__resolve_json' {
            # Output: single-line JSON with everything a *remote* caller needs.
            # `wtw --on <host> …` runs this over ssh, because the machine that
            # owns the worktree is the only one that knows where it currently is.
            # Deliberately not an extra field on __resolve: the zsh/bash wrappers
            # read that one with fixed positional fields.
            if ($pos.Count -eq 0) { Write-Error "Usage: wtw __resolve_json <name>"; return }
            $target = & { Resolve-WtwTarget (Join-WtwTargetName $pos) } 6>$null
            if (-not $target) { exit 1 }
            $p = if ($target.WorktreeEntry) { $target.WorktreeEntry.path } else { $target.RepoEntry.mainPath }
            $ws = if ($target.WorktreeEntry) {
                Get-WtwPropertyValue -Object $target.WorktreeEntry -Name 'workspace'
            } else {
                Get-WtwPropertyValue -Object $target.RepoEntry -Name 'templateWorkspace'
            }
            # A workspace path recorded in the registry but since deleted would
            # produce a --file-uri that opens an empty window; drop it here so the
            # caller falls back to a folder open.
            if ($ws -and -not (Test-Path $ws)) { $ws = $null }
            $c = if ($target.WorktreeEntry) {
                Get-WtwPropertyValue -Object $target.WorktreeEntry -Name 'color'
            } else {
                Get-WtwPropertyValue -Object (Get-WtwColors).assignments -Name "$($target.RepoName)/main"
            }
            $display = Resolve-WtwTerminalWorkspaceMetadata -Target $target
            [PSCustomObject]@{
                path       = $p
                workspace  = $ws
                color      = $c
                title      = if ($target.TaskName) { "$($target.RepoName)/$($target.TaskName)" } else { $target.RepoName }
                prettyName = if ($display) { $display.PrettyName } else { $null }
                repo       = $target.RepoName
                repoEmoji  = (Get-WtwRepoEmoji -RepoEntry $target.RepoEntry)
                task       = $target.TaskName
            } | ConvertTo-Json -Compress -Depth 5 | Write-Output
        }
        '__resolve' {
            # Output: path\tcolor\ttitle\tstartup_script\tworktree_id\tworktree_index
            # Used by wtw.zsh/wtw.bash — must be clean stdout (no Write-WtwHost noise)
            # Optional: --shell zsh|bash to resolve per-shell session script
            if ($pos.Count -eq 0) { Write-Error "Usage: wtw __resolve <name> [--shell zsh|bash]"; return }
            $shellType = $splat['Shell'] ?? ''
            $target = & { Resolve-WtwTarget (Join-WtwTargetName $pos) } 6>$null
            if (-not $target) { exit 1 }
            $p = if ($target.WorktreeEntry) { $target.WorktreeEntry.path } else { $target.RepoEntry.mainPath }
            $c = if ($target.WorktreeEntry) {
                $target.WorktreeEntry.color
            } else {
                Get-WtwPropertyValue -Object (Get-WtwColors).assignments -Name "$($target.RepoName)/main"
            }
            $t = if ($target.TaskName) { "$($target.RepoName)/$($target.TaskName)" } else { $target.RepoName }
            $s = Resolve-WtwSessionScript -RepoEntry $target.RepoEntry -Shell $shellType
            # Compute worktree index for env vars
            $wtId = $target.TaskName ?? ''
            $wtIndex = 0
            if ($target.TaskName -and $target.RepoEntry.worktrees) {
                $i = 1
                foreach ($tn in (Get-WtwPropertyNames -Object $target.RepoEntry.worktrees)) {
                    if ($tn -eq $target.TaskName) { $wtIndex = $i; break }
                    $i++
                }
            }
            Write-Output "${p}`t${c}`t${t}`t${s}`t${wtId}`t${wtIndex}"
        }
        '__aliases' {
            # Output: alias_name\tpath\tcolor\ttitle\tstartup_script\tworktree_id\tworktree_index
            # Optional: --shell zsh|bash to resolve per-shell session scripts
            $shellType = $splat['Shell'] ?? ''
            $registry = Get-WtwRegistry
            $colors = Get-WtwColors
            foreach ($repoName in (Get-WtwPropertyNames -Object $registry.repos)) {
                $repo = $registry.repos.$repoName
                $aliases = Get-WtwRepoAliases $repo
                $ss = Resolve-WtwSessionScript -RepoEntry $repo -Shell $shellType
                $mainColor = Get-WtwPropertyValue -Object $colors.assignments -Name "$repoName/main" -DefaultValue ''
                foreach ($a in $aliases) {
                    Write-Output "${a}`t$($repo.mainPath)`t${mainColor}`t${repoName}`t${ss}`t`t0"
                }
                if ($repo.worktrees) {
                    $wtIdx = 1
                    foreach ($taskName in (Get-WtwPropertyNames -Object $repo.worktrees)) {
                        $wt = $repo.worktrees.$taskName
                        $wtColor = Get-WtwPropertyValue -Object $wt -Name 'color' -DefaultValue ''
                        $wtTitle = "$repoName/$taskName"
                        foreach ($a in $aliases) {
                            Write-Output "${a}-${taskName}`t$($wt.path)`t${wtColor}`t${wtTitle}`t${ss}`t${taskName}`t${wtIdx}"
                        }
                        foreach ($custom in (Get-WtwWorktreeAliases $wt)) {
                            $shellName = ConvertTo-WtwShellAliasName $custom
                            if ($shellName) {
                                Write-Output "${shellName}`t$($wt.path)`t${wtColor}`t${wtTitle}`t${ss}`t${taskName}`t${wtIdx}"
                            }
                        }
                        $wtIdx++
                    }
                }
            }
        }
        '__cmux_apply_current' {
            # Called silently by shell integration when a terminal starts inside
            # cmux. Socket commands are allowed from inside cmux, unlike the
            # external app-open fallback path.
            Initialize-WtwCmuxCurrentSession
        }
        '__cmux_init_current' {
            # PowerShell cmux startup path. Applies the normal wtw terminal title,
            # env vars, and session script for the cwd target, then refreshes cmux
            # workspace metadata. Inside a remote SSH workspace this is
            # ``wtw --on <host> go [name]``.
            Initialize-WtwCmuxCurrentSession -ApplyTerminalSession
        }
        '__cmux_remote_shell' {
            # Command Palette / tab-bar "pwsh": SSH into the current remote
            # project when this workspace is a wtw-remote session, otherwise
            # a nested local pwsh (same as the old tab body).
            if (-not (Connect-WtwCmuxCurrentRemoteSession)) {
                & pwsh -NoLogo
            }
        }
        default   {
            # Check if command is an editor shortcut (cursor, cur, code, co, anti, etc.)
            $resolvedEditor = Resolve-WtwEditorCommand $Command
            if ($resolvedEditor) {
                $splat['Editor'] = $resolvedEditor
                if ($pos.Count -gt 0) { $splat['Name'] = Join-WtwTargetName $pos }
                Open-WtwWorkspace @splat
            } else {
                # Fallback: treat unknown command as "go <name>"
                $implicitName = Join-WtwTargetName (@($Command) + @($pos))
                Write-WtwHost "  → " -ForegroundColor DarkGray -NoNewline
                Write-WtwHost "wtw $implicitName" -ForegroundColor White -NoNewline
                Write-WtwHost "  interpreted as  " -ForegroundColor DarkGray -NoNewline
                Write-WtwHost "wtw go $implicitName" -ForegroundColor Cyan
                Enter-WtwWorktree -Name $implicitName @splat
            }
        }
    }
}
