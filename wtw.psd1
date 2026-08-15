@{
    RootModule        = 'wtw.psm1'
    ModuleVersion     = '0.2.3'
    GUID              = 'a3f7e8d1-4b2c-4e9a-b5d6-8c1f3a7e9d2b'
    Author            = 'Sergey Novikov'
    CompanyName       = 'logificiel'
    Copyright         = '(c) 2025-present Sergey Novikov. All rights reserved.'
    Description       = 'Git worktree + VS Code/(vscode based editors like Cursor) workspace manager. Creates, switches, and removes worktrees with auto-generated workspace files, unique Peacock colors, shell aliases, and fuzzy name resolution.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Add-WtwEntry'
        'Copy-WtwWorkspace'
        'Enter-WtwWorktree'
        'Get-WtwList'
        'Get-WtwUpdateStatus'
        'Get-WtwWindowTitle'
        'Initialize-WtwConfig'
        'Install-Wtw'
        'Install-WtwSkill'
        'Invoke-Wtw'
        'Invoke-WtwClean'
        'Invoke-WtwHost'
        'New-WtwWorkspace'
        'New-WtwWorktree'
        'Open-WtwWorkspace'
        'Register-WtwProfile'
        'Register-WtwTerminalTitle'
        'Remove-WtwWorktree'
        'Set-WtwColor'
        'Sync-WtwWorkspace'
        'Unregister-WtwEntry'
    )
    AliasesToExport   = @('wtw')
    CmdletsToExport   = @()
    VariablesToExport = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('git', 'worktree', 'vscode', 'cursor', 'workspace', 'peacock', 'devtools', 'ssh', 'remote')
            LicenseUri   = 'https://github.com/serrnovik/wtw/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/serrnovik/wtw'
            ReleaseNotes = 'Adds remote worktrees: `wtw --on <host> cursor <name>` opens a worktree that lives on another machine over Remote-SSH, discovering it by asking that machine''s own wtw rather than mirroring its registry. `wtw host` manages those machines and keeps ~/.ssh/config.d/wtw in sync, since the editor resolves hosts through the ssh client: `discover` registers everything on your tailnet (Tailscale, taking the platform from it and skipping devices that cannot host a worktree), `show` describes the effective config, `trust` compares host-key fingerprints against ones you already trust, and `test` diagnoses a failure across addresses, ssh config and the remote wtw. Addresses are an ordered candidate list probed at sync time, classified by transport (tailscale / zerotier / mdns / lan); `--via` picks one, either persistently via `host add` or for a single command via `wtw --on <host> <cmd> --via <transport>`. `editor` in the config now also accepts an ordered chain (["cursor","code"]) — first runnable wins. Workspace colors now pick their foreground by WCAG contrast ratio instead of a brightness threshold, so chrome text stays readable on mid-tone palette entries in both light and dark themes, and the active tab gets a border so the current file is identifiable by more than its fill. Internally, the VS Code family (prefixes, CLI candidates, app bundles, Remote-SSH extension ids, settings dirs) comes from one table instead of four lists that could drift.'
        }
    }
}

