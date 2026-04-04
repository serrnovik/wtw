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
            'Enter-WtwWorktree', 'Open-WtwWorkspace', 'Remove-WtwWorktree',
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
}
