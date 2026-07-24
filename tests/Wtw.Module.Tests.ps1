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
}
