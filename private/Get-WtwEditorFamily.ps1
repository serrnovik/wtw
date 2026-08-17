function Get-WtwEditorFamily {
    <#
    .SYNOPSIS
        The VS Code editor family table — single source of truth.
    .DESCRIPTION
        Every VS Code fork wtw supports shares four capabilities: a CLI that
        takes a path, `--list-extensions`, a user `settings.json`, and support
        for `vscode-remote://` authorities. That shared shape is what makes them
        a family; SourceGit / T3 / ChatGPT / cmux / Superset share none of it and
        stay `type`-tagged special cases in Resolve-WtwEditorCommand.

        Before this table the same five editors were listed in four places —
        Resolve-WtwEditorCommand (prefixes), Invoke-WtwEditorCli (CLI candidates
        + app bundles), Install-Wtw (detection + mac hints), and the completion
        script. They drifted: the Antigravity v1→v2 CLI rename fixed launch-time
        invocation but not install-time detection. Remote-SSH would have added a
        fifth and sixth list (extension id, settings dir), so the lists are now
        projections of this one.

        Member fields:
          Id           Canonical name — also the CLI name wtw resolves to.
          Name         Display name used in install output.
          Prefixes     CLI shortcuts, longest-lived first (matched by prefix).
          Cli          Ordered CLI candidates, newest first. Survives renames.
          MacApps      Ordered /Applications bundle names. Index-paired with Cli
                       when the counts match, so Antigravity IDE.app maps to
                       antigravity-ide and Antigravity.app to antigravity.
          LaunchFlags  Flags always passed before the path.
          RemoteExts   Ordered Remote-SSH extension ids. VSCodium cannot use
                       Microsoft's (proprietary, absent from Open VSX), hence a
                       per-member list rather than one shared constant.
          SettingsDirs Ordered config-dir candidates under the platform's user
                       settings root. First existing wins.
    .OUTPUTS
        Ordered array of hashtables. Order is significant: Resolve-WtwEditorCommand
        matches prefixes in this order, so `wtw c...` keeps resolving to Cursor.
    #>
    [CmdletBinding()]
    param()

    return @(
        @{
            Id           = 'cursor'
            Name         = 'Cursor'
            Prefixes     = @('cursor', 'cur')
            Cli          = @('cursor')
            MacApps      = @('Cursor')
            # Cursor otherwise follows its last-window behaviour, which can route a
            # workspace into a standalone Agent window rather than a project IDE.
            # wtw worktrees need their own IDE window so the project context stays
            # unambiguous.
            LaunchFlags  = @('--new-window')
            RemoteExts   = @('anysphere.remote-ssh')
            SettingsDirs = @('Cursor')
        }
        @{
            Id           = 'code'
            Name         = 'VS Code'
            Prefixes     = @('code', 'co')
            Cli          = @('code')
            MacApps      = @('Visual Studio Code')
            LaunchFlags  = @()
            RemoteExts   = @('ms-vscode-remote.remote-ssh')
            SettingsDirs = @('Code')
        }
        @{
            Id           = 'antigravity'
            Name         = 'Antigravity'
            Prefixes     = @('antigravity', 'anti', 'ag')
            # v2 ships its CLI as `antigravity-ide` (app: "Antigravity IDE.app")
            # while the v1 installer's `~/.antigravity/.../bin/antigravity` stub
            # lingers and points at a binary that no longer exists.
            Cli          = @('antigravity-ide', 'antigravity')
            MacApps      = @('Antigravity IDE', 'Antigravity')
            LaunchFlags  = @()
            RemoteExts   = @('google.antigravity-remote-ssh', 'ms-vscode-remote.remote-ssh')
            SettingsDirs = @('Antigravity IDE', 'Antigravity')
        }
        @{
            Id           = 'windsurf'
            Name         = 'Windsurf'
            Prefixes     = @('windsurf', 'wind', 'ws')
            Cli          = @('windsurf')
            MacApps      = @('Windsurf')
            LaunchFlags  = @()
            RemoteExts   = @('codeium.windsurf-remote-openssh', 'jeanp413.open-remote-ssh')
            SettingsDirs = @('Windsurf')
        }
        @{
            Id           = 'codium'
            Name         = 'VSCodium'
            Prefixes     = @('codium', 'vscodium')
            Cli          = @('codium')
            MacApps      = @('VSCodium')
            LaunchFlags  = @()
            # Microsoft's Remote-SSH is proprietary and not published to Open VSX,
            # so VSCodium needs the community fork instead.
            RemoteExts   = @('jeanp413.open-remote-ssh')
            SettingsDirs = @('VSCodium')
        }
    )
}

function Get-WtwEditorFamilyMember {
    <#
    .SYNOPSIS
        Look up one family member by its canonical id.
    .PARAMETER Id
        Canonical editor id (e.g. 'cursor'). Not a prefix — use
        Resolve-WtwEditorFamilyMember for shortcut resolution.
    .OUTPUTS
        The member hashtable, or $null when the id is not a family editor.
    #>
    [CmdletBinding()]
    param([AllowNull()][string] $Id)

    if (-not $Id) { return $null }
    return (Get-WtwEditorFamily | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)
}

function Resolve-WtwEditorFamilyMember {
    <#
    .SYNOPSIS
        Resolve a user-typed shortcut to a family member.
    .DESCRIPTION
        Same prefix semantics as Resolve-WtwEditorCommand, but returns the whole
        member so callers needing RemoteExts / SettingsDirs don't have to resolve
        the id and then look it up again.
    .PARAMETER Name
        Editor name or shortcut ('cur', 'cursor', 'co', ...).
    #>
    [CmdletBinding()]
    param([AllowNull()][string] $Name)

    if (-not $Name) { return $null }

    foreach ($member in Get-WtwEditorFamily) {
        foreach ($prefix in $member.Prefixes) {
            if ($prefix -eq $Name -or $prefix.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $member
            }
        }
    }
    return $null
}

function Get-WtwEditorMacCliHints {
    <#
    .SYNOPSIS
        macOS "CLI is missing but the app is installed" probes for one member.
    .DESCRIPTION
        Derived from MacApps + Cli rather than a second hand-maintained table.
        When the two lists are the same length they are paired by index (so
        "Antigravity IDE.app" pairs with `antigravity-ide`); otherwise every
        combination is emitted. Either way the caller filters by Test-Path, so a
        wrong pairing simply never matches.
    .OUTPUTS
        Array of @{ App; Bin; Name } — the bundle, its bundled CLI, and the CLI name.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Member)

    $apps = @($Member.MacApps)
    $clis = @($Member.Cli)
    if ($apps.Count -eq 0 -or $clis.Count -eq 0) { return @() }

    $pairs = if ($apps.Count -eq $clis.Count) {
        0..($apps.Count - 1) | ForEach-Object { @{ App = $apps[$_]; Cli = $clis[$_] } }
    } else {
        foreach ($app in $apps) { foreach ($cli in $clis) { @{ App = $app; Cli = $cli } } }
    }

    # Comma operator: a bare `return @(...)` unrolls a one-element array back to
    # the hashtable itself, and `$hints[0]` on a hashtable is a key lookup that
    # silently yields $null. Every family member with a single bundle hits this.
    return , @($pairs | ForEach-Object {
            @{
                App  = "/Applications/$($_.App).app"
                Bin  = "/Applications/$($_.App).app/Contents/Resources/app/bin/$($_.Cli)"
                Name = $_.Cli
            }
        })
}

function Get-WtwEditorSettingsPath {
    <#
    .SYNOPSIS
        Path to a family member's user settings.json on this platform.
    .DESCRIPTION
        VS Code forks keep user settings under a per-app directory in the
        platform's roaming-config root. Returns the first candidate whose User
        directory already exists — wtw never creates an editor's profile
        directory, so a not-installed editor yields $null instead of a path that
        would materialise a phantom profile.
    .PARAMETER Member
        Family member hashtable.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Member)

    $root = if ($IsWindows) {
        $env:APPDATA
    } elseif ($IsMacOS) {
        Join-Path $HOME 'Library' 'Application Support'
    } else {
        if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
    }
    if (-not $root) { return $null }

    foreach ($dir in @($Member.SettingsDirs)) {
        $userDir = Join-Path $root $dir 'User'
        if (Test-Path $userDir) { return (Join-Path $userDir 'settings.json') }
    }
    return $null
}
