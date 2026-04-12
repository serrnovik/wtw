BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Get-WtwRepoAliases' {
    It 'returns array from aliases field' {
        $repo = [PSCustomObject]@{ aliases = @('p1', 'myapp') }
        $result = Get-WtwRepoAliases $repo
        $result | Should -Contain 'p1'
        $result | Should -Contain 'myapp'
        $result.Count | Should -Be 2
    }

    It 'returns array from legacy alias field' {
        $repo = [PSCustomObject]@{ alias = 'p1' }
        $result = Get-WtwRepoAliases $repo
        $result | Should -Contain 'p1'
        $result.Count | Should -Be 1
    }

    It 'returns empty array when no aliases' {
        $repo = [PSCustomObject]@{ mainPath = '/some/path' }
        $result = Get-WtwRepoAliases $repo
        $result.Count | Should -Be 0
    }
}

Describe 'Test-WtwAliasMatch' {
    It 'matches when name is in aliases array' {
        $repo = [PSCustomObject]@{ aliases = @('p1', 'myapp') }
        Test-WtwAliasMatch $repo 'p1' | Should -BeTrue
        Test-WtwAliasMatch $repo 'myapp' | Should -BeTrue
    }

    It 'does not match unknown alias' {
        $repo = [PSCustomObject]@{ aliases = @('p1') }
        Test-WtwAliasMatch $repo 'evx1' | Should -BeFalse
    }

    It 'matches legacy alias field' {
        $repo = [PSCustomObject]@{ alias = 'p1' }
        Test-WtwAliasMatch $repo 'p1' | Should -BeTrue
    }
}
