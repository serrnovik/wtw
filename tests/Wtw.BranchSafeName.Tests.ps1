BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    . "$PSScriptRoot/../private/ConvertTo-WtwBranchSafeName.ps1"
}

Describe 'ConvertTo-WtwBranchSafeName' {
    It 'maps spaces to underscores' {
        ConvertTo-WtwBranchSafeName -Name 'XXX YYY ZZ' | Should -Be 'XXX_YYY_ZZ'
    }

    It 'collapses multiple spaces' {
        ConvertTo-WtwBranchSafeName -Name 'a   b' | Should -Be 'a_b'
    }

    It 'trims outer whitespace' {
        ConvertTo-WtwBranchSafeName -Name '  foo bar  ' | Should -Be 'foo_bar'
    }

    It 'leaves simple slugs unchanged' {
        ConvertTo-WtwBranchSafeName -Name 'feature_123' | Should -Be 'feature_123'
    }

    It 'replaces path-hostile characters' {
        ConvertTo-WtwBranchSafeName -Name 'a/b:c*d' | Should -Be 'a_b_c_d'
    }

    It 'strips leading dots and hyphens' {
        ConvertTo-WtwBranchSafeName -Name '...foo' | Should -Be 'foo'
    }

    It 'returns empty for whitespace-only' {
        ConvertTo-WtwBranchSafeName -Name '   ' | Should -Be ''
    }
}
