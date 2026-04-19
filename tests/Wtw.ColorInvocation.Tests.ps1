BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    . "$PSScriptRoot/../private/Resolve-WtwColorArgs.ps1"
}

Describe 'Resolve-WtwColorArgs' {
    It 'binds single argument "random" to Color' {
        $result = Resolve-WtwColorArgs @('random')
        $result['Color'] | Should -Be 'random'
        $result.ContainsKey('Name') | Should -Be $false
    }

    It 'binds single argument hex to Color' {
        $result = Resolve-WtwColorArgs @('#abcdef')
        $result['Color'] | Should -Be '#abcdef'
        $result.ContainsKey('Name') | Should -Be $false
    }

    It 'binds single argument that is neither to Name' {
        $result = Resolve-WtwColorArgs @('my-repo')
        $result['Name'] | Should -Be 'my-repo'
        $result.ContainsKey('Color') | Should -Be $false
    }

    It 'binds two arguments to Name and Color' {
        $result = Resolve-WtwColorArgs @('my-repo', 'random')
        $result['Name'] | Should -Be 'my-repo'
        $result['Color'] | Should -Be 'random'
    }
}
