BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Get-WtwRepoAliases' {
    It 'returns array from aliases field' {
        $repo = [PSCustomObject]@{ aliases = @('sn3', 'snowmain3') }
        $result = Get-WtwRepoAliases $repo
        $result | Should -Contain 'sn3'
        $result | Should -Contain 'snowmain3'
        $result.Count | Should -Be 2
    }

    It 'returns array from legacy alias field' {
        $repo = [PSCustomObject]@{ alias = 'sn3' }
        $result = Get-WtwRepoAliases $repo
        $result | Should -Contain 'sn3'
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
        $repo = [PSCustomObject]@{ aliases = @('sn3', 'snowmain3') }
        Test-WtwAliasMatch $repo 'sn3' | Should -BeTrue
        Test-WtwAliasMatch $repo 'snowmain3' | Should -BeTrue
    }

    It 'does not match unknown alias' {
        $repo = [PSCustomObject]@{ aliases = @('sn3') }
        Test-WtwAliasMatch $repo 'evx1' | Should -BeFalse
    }

    It 'matches legacy alias field' {
        $repo = [PSCustomObject]@{ alias = 'sn3' }
        Test-WtwAliasMatch $repo 'sn3' | Should -BeTrue
    }
}
