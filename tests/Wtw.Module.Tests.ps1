BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'wtw module loading' {
    It 'exports Invoke-Wtw function' {
        Get-Command Invoke-Wtw -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'exports all public functions' {
        $expected = @(
            'Invoke-Wtw', 'Initialize-WtwConfig', 'New-WtwWorktree', 'Get-WtwList',
            'Enter-WtwWorktree', 'Open-WtwWorkspace', 'Remove-WtwWorktree', 'Unregister-WtwEntry',
            'Edit-WtwEntry',
            'Invoke-WtwClean', 'New-WtwWorkspace', 'Copy-WtwWorkspace',
            'Sync-WtwWorkspace', 'Install-Wtw', 'Register-WtwProfile'
        )
        foreach ($fn in $expected) {
            Get-Command $fn -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty -Because "$fn should be exported"
        }
    }

    It 'registers the wtw alias' {
        Get-Alias wtw -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'enforces strict mode inside the module' {
        InModuleScope wtw {
            { $script:_WtwUndefinedStrictModeProbe } | Should -Throw
        }
    }

    It 'enumerates empty object properties safely under strict mode' {
        InModuleScope wtw {
            $empty = [PSCustomObject]@{}

            (Get-WtwPropertyNames -Object $empty).Count | Should -Be 0
            Get-WtwPropertyValue -Object $empty -Name 'missing' -DefaultValue 'fallback' |
                Should -Be 'fallback'
        }
    }

    # Editor descriptors from Resolve-WtwEditorCommand are hashtables, and
    # PSObject.Properties on a hashtable exposes Count/Keys/Values instead of the
    # keys. Without the IDictionary branch every lookup silently returned the
    # default, which is what made `wtw t3` miss "T3 Code (Alpha).app".
    It 'reads hashtable keys rather than the .NET surface' {
        InModuleScope wtw {
            $editor = @{ type = 'macapp'; appName = 'T3 Code'; appNameCandidates = @('T3 Code', 'T3 Code (Alpha)') }

            $names = Get-WtwPropertyNames -Object $editor
            ($names | Sort-Object) | Should -Be @('appName', 'appNameCandidates', 'type')
            Get-WtwPropertyValue -Object $editor -Name 'appNameCandidates' -DefaultValue @('T3 Code') |
                Should -Be @('T3 Code', 'T3 Code (Alpha)')
            Get-WtwPropertyValue -Object $editor -Name 'macArgsViaCli' -DefaultValue $false |
                Should -BeFalse
            (Get-WtwPropertyNames -Object @{}).Count | Should -Be 0
        }
    }
}

Describe 'Get-WtwWorkspaceRecordedColor under the module StrictMode' {
    It 'returns nothing for the shipped minimal template' {
        InModuleScope wtw {
            $templatePath = Join-Path $script:WtwModuleRoot 'templates' 'minimal.code-workspace.template'
            $workspace = Read-JsoncFile $templatePath

            { Get-WtwWorkspaceRecordedColor -Workspace $workspace } | Should -Not -Throw
            Get-WtwWorkspaceRecordedColor -Workspace $workspace | Should -BeNullOrEmpty
        }
    }

    It 'prefers wtw.color and falls back to peacock.color' {
        InModuleScope wtw {
            $withCurrent = [PSCustomObject]@{
                settings = [PSCustomObject]@{
                    'wtw.color'     = '#111111'
                    'peacock.color' = '#222222'
                }
            }
            $legacyOnly = [PSCustomObject]@{
                settings = [PSCustomObject]@{ 'peacock.color' = '#222222' }
            }

            Get-WtwWorkspaceRecordedColor -Workspace $withCurrent | Should -Be '#111111'
            Get-WtwWorkspaceRecordedColor -Workspace $legacyOnly | Should -Be '#222222'
        }
    }
}
