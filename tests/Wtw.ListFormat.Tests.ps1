BeforeAll {
    . "$PSScriptRoot/../private/Get-WtwListFormatHelpers.ps1"
}

Describe 'Get-WtwEllipsisText' {
    It 'leaves short strings unchanged' {
        Get-WtwEllipsisText -Text 'hello' -MaxLength 10 -Mode End | Should -Be 'hello'
    }

    It 'truncates at End' {
        $ellipsisChar = [char]0x2026
        $result = Get-WtwEllipsisText -Text 'abcdefghijklmnopqrst' -MaxLength 8 -Mode End
        $result.Length | Should -Be 8
        $result.EndsWith($ellipsisChar) | Should -Be $true
    }

    It 'truncates in the Middle' {
        $ellipsisChar = [char]0x2026
        $result = Get-WtwEllipsisText -Text '0123456789abcdef' -MaxLength 10 -Mode Middle
        $result.Contains($ellipsisChar) | Should -Be $true
        $result.StartsWith('012') | Should -Be $true
        $result.EndsWith('cdef') | Should -Be $true
    }
}

Describe 'ConvertTo-WtwShortDisplayPath' {
    It 'applies middle ellipsis to long paths' {
        $longPath = '/tmp/' + ('x' * 50)
        $result = ConvertTo-WtwShortDisplayPath -Path $longPath -MaxLength 24
        $result.Contains([char]0x2026) | Should -Be $true
        $result.Length | Should -BeLessOrEqual 28
    }

    It 'replaces HOME with tilde when path is under HOME' {
        $homeDirectory = $HOME
        if (-not [string]::IsNullOrEmpty($homeDirectory)) {
            $longPath = Join-Path $homeDirectory 'Data/snogit/myproject'
            $result = ConvertTo-WtwShortDisplayPath -Path $longPath -MaxLength 120
            ($result.StartsWith('~/') -or $result.StartsWith('~\')) | Should -Be $true
        }
    }

    It 'preserves (MISSING) suffix after truncation' {
        $result = ConvertTo-WtwShortDisplayPath -Path '/tmp/x/very/long/path/that/needs/truncation (MISSING)' -MaxLength 40
        $result | Should -Match ' \(MISSING\)$'
    }
}

Describe 'Get-WtwNarrowAliasesColumn' {
    It 'returns first alias-task only for worktree rows' {
        $s = 'sn1-my-task, snowmain1-my-task, sn-my-task'
        Get-WtwNarrowAliasesColumn -AliasesJoined $s -Kind 'wt' | Should -Be 'sn1-my-task'
    }

    It 'abbreviates many repo aliases (stacked lines)' {
        $s = 'a, b, c, d'
        $expected = "a`nb`n(+2)"
        Get-WtwNarrowAliasesColumn -AliasesJoined $s -Kind 'repo' | Should -Be $expected
    }

    It 'joins two repo aliases on separate lines' {
        $s = 'a, b'
        Get-WtwNarrowAliasesColumn -AliasesJoined $s -Kind 'repo' | Should -Be "a`nb"
    }
}
