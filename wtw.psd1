@{
    RootModule        = 'wtw.psm1'
    ModuleVersion     = '0.2.20'
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
            ReleaseNotes = 'cmux AppleScript fallback types POSIX into zsh (`cd` + `wtw __cmux_apply_current`) instead of PowerShell `Set-Location`. zsh/bash `wtw` passes `__*` hooks and `--on`/`--at` through to pwsh.'
        }
    }
}

