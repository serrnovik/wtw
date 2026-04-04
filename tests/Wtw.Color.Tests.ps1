BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    . "$PSScriptRoot/../private/ConvertTo-PeacockColorBlock.ps1"
}

Describe 'ConvertTo-PeacockColorBlock' {
    It 'returns an ordered hashtable with expected keys' {
        $result = ConvertTo-PeacockColorBlock '#e05d44'
        $result | Should -Not -BeNullOrEmpty
        $result.Keys | Should -Contain 'titleBar.activeBackground'
        $result.Keys | Should -Contain 'peacock.color' -Not
        # peacock.color is set separately, not in the block
        $result.Keys | Should -Contain 'activityBar.activeBackground'
        $result.Keys | Should -Contain 'statusBarItem.remoteBackground'
    }

    It 'uses the base color for titleBar.activeBackground' {
        $result = ConvertTo-PeacockColorBlock '#2285a6'
        $result['titleBar.activeBackground'] | Should -Be '#2285a6'
    }

    It 'uses the base color for statusBarItem.remoteBackground' {
        $result = ConvertTo-PeacockColorBlock '#007ec6'
        $result['statusBarItem.remoteBackground'] | Should -Be '#007ec6'
    }

    It 'generates inactive background with alpha suffix' {
        $result = ConvertTo-PeacockColorBlock '#e05d44'
        $result['titleBar.inactiveBackground'] | Should -Match '^#[0-9a-f]{6}99$'
    }
}

Describe 'Lighten-HexColor' {
    It 'lightens a color' {
        $result = Lighten-HexColor '#000000' -Factor 0.5
        $result | Should -Be '#808080'
    }

    It 'white stays white' {
        $result = Lighten-HexColor '#ffffff' -Factor 0.5
        $result | Should -Be '#ffffff'
    }
}

Describe 'Darken-HexColor' {
    It 'darkens a color' {
        $result = Darken-HexColor '#ffffff' -Factor 0.5
        $result | Should -Be '#808080'
    }

    It 'black stays black' {
        $result = Darken-HexColor '#000000' -Factor 0.5
        $result | Should -Be '#000000'
    }
}

Describe 'Get-ContrastForeground' {
    It 'returns light foreground for dark colors' {
        $result = Get-ContrastForeground '#000000'
        $result | Should -Be '#e7e7e7'
    }

    It 'returns dark foreground for light colors' {
        $result = Get-ContrastForeground '#ffffff'
        $result | Should -Be '#15202b'
    }
}
