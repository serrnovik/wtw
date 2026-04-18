BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    # Dot-source the public file containing Convert-WtwArgsToSplat (it's not exported but defined in public/)
    . "$PSScriptRoot/../private/Convert-WtwArgsToSplat.ps1"
}

Describe 'Convert-WtwArgsToSplat' {
    It 'parses positional args' {
        $result = Convert-WtwArgsToSplat @('myarg')
        $result.Positional | Should -Contain 'myarg'
        $result.Splat.Count | Should -Be 0
    }

    It 'parses -Switch as switch parameter' {
        $result = Convert-WtwArgsToSplat @('-Force')
        $result.Splat['Force'] | Should -BeTrue
        $result.Positional.Count | Should -Be 0
    }

    It 'parses -Param value as named parameter' {
        $result = Convert-WtwArgsToSplat @('-Branch', 'main')
        $result.Splat['Branch'] | Should -Be 'main'
        $result.Positional.Count | Should -Be 0
    }

    It 'translates --kebab-case to PascalCase' {
        $result = Convert-WtwArgsToSplat @('--dry-run')
        $result.Splat['DryRun'] | Should -BeTrue
    }

    It 'translates --kebab-case with value' {
        $result = Convert-WtwArgsToSplat @('--code-folder', '/some/path')
        $result.Splat['CodeFolder'] | Should -Be '/some/path'
    }

    It 'handles mixed positional and named args' {
        $result = Convert-WtwArgsToSplat @('mytask', '--branch', 'feat/x', '--force')
        $result.Positional | Should -Contain 'mytask'
        $result.Splat['Branch'] | Should -Be 'feat/x'
        $result.Splat['Force'] | Should -BeTrue
    }

    It 'returns empty for no args' {
        $result = Convert-WtwArgsToSplat @()
        $result.Positional.Count | Should -Be 0
        $result.Splat.Count | Should -Be 0
    }
}
