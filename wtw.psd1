@{
    RootModule        = 'wtw.psm1'
    ModuleVersion     = '0.2.34'
    GUID              = 'a3f7e8d1-4b2c-4e9a-b5d6-8c1f3a7e9d2b'
    Author            = 'Sergey Novikov'
    CompanyName       = 'logificiel'
    Copyright         = '(c) 2025-present Sergey Novikov. All rights reserved.'
    Description       = 'Git worktree + VS Code/(vscode based editors like Cursor) workspace manager. Creates, switches, and removes worktrees with auto-generated workspace files, unique Peacock colors, shell aliases, and fuzzy name resolution.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Add-WtwEntry'
        'Copy-WtwWorkspace'
        'Edit-WtwEntry'
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
        'Update-Wtw'
    )
    AliasesToExport   = @('wtw')
    CmdletsToExport   = @()
    VariablesToExport = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('git', 'worktree', 'vscode', 'cursor', 'workspace', 'peacock', 'devtools', 'ssh', 'remote')
            LicenseUri   = 'https://github.com/serrnovik/wtw/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/serrnovik/wtw'
            ReleaseNotes = 'wtw cmux places each workspace in a cmux sidebar group per machine/project (🍏SP/🎸 snowmain1, 🧊AT/🎭 kulissa-landing). Set this machine''s badge with `wtw host self --emoji --label` (alias: `wtw self`). Remote cmux workspaces open two SSH tabs (🌴 wtw + pwsh) and stamp WTW_REMOTE_HOST / WTW_REMOTE_NAME so Command Palette 🌴 wtw and pwsh SSH into the same remote project. The 🌴 wtw title guard keeps the worktree tab name (🖥️🌳 …) instead of snapping back to 🌴 wtw. `wtw list -f/--filter` keeps matching repos and worktrees. Host output follows shell-theme. Install/update/publish rewrite wtw.zsh/wtw.bash to LF.'
        }
    }
}

