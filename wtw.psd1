@{
    RootModule        = 'wtw.psm1'
    ModuleVersion     = '0.2.11'
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
            ReleaseNotes = '`wtw update` replaces the installed copy at ~/.wtw/module with the latest PowerShell Gallery release, and is now a separate command from `wtw install`, which installs the checkout you run it from. The two used to be aliases, so `wtw update` from a normal shell hit the self-install guard and refused to do anything. Which command wtw offers depends on how the running copy was installed: `wtw install` records that in ~/.wtw/module/INSTALLATION.json, and the once-per-session update notice reads it, so a hand-installed copy is no longer told to run `Update-Module wtw` — a command that either errors or updates a copy no loader imports, since the profile snippet, the zsh and bash wrappers and the Windows cmd shim all name ~/.wtw/module/wtw.psm1 by path. A leftover `Install-Module wtw` on PSModulePath is reported and can be removed, because a bare `Import-Module wtw` resolves to that one instead. A local build newer than the published release, or the same version, is reported as current rather than as a problem. `--at` is accepted as an alias of `--on`. Workspace colours now cover every key the Peacock extension also writes, including the command centre, status bar and horizontal activity bar, so nothing is left for it to fill in; wtw records the colour as `wtw.color` rather than `peacock.color`, which is what stopped Peacock re-applying its own palette — in Cursor it forces the title bar and command centre foreground to #595959 whatever the background is. Generated window titles drop the literal spaces around ${separator} so an editor-less window reads "name — Cursor" instead of "name —   — Cursor", and the selected file shows once one is open.'
        }
    }
}

