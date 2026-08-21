BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'ConvertTo-PeacockColorBlock' {
    It 'returns an ordered hashtable with expected keys' {
        $result = ConvertTo-PeacockColorBlock '#e05d44'
        $result | Should -Not -BeNullOrEmpty
        $result.Keys | Should -Contain 'titleBar.activeBackground'
        $result.Keys | Should -Contain 'wtw.color' -Not
        # wtw.color is set separately, not in the block
        $result.Keys | Should -Contain 'activityBar.activeBackground'
        $result.Keys | Should -Contain 'statusBarItem.remoteBackground'
        $result.Keys | Should -Contain 'commandCenter.activeForeground'
        $result.Keys | Should -Contain 'commandCenter.inactiveForeground'
        # Every key the Peacock extension would otherwise fill in itself, so an
        # editor that also has Peacock installed has nothing left to "correct".
        $result.Keys | Should -Contain 'commandCenter.foreground'
        $result.Keys | Should -Contain 'titleBar.activeForeground'
        $result.Keys | Should -Contain 'statusBar.foreground'
        $result.Keys | Should -Contain 'activityBar.foreground'
        $result.Keys | Should -Contain 'activityBarTop.foreground'
    }

    It 'gives every foreground at least WCAG AA contrast against the color it sits on' {
        foreach ($base in @('#e05d44', '#b01ad5', '#96dd2c', '#00ffff', '#f9a825', '#0000ff', '#ffff00')) {
            $result = ConvertTo-PeacockColorBlock $base
            foreach ($pair in @(
                    @('titleBar.activeForeground', 'titleBar.activeBackground'),
                    @('commandCenter.foreground', 'titleBar.activeBackground'),
                    @('statusBar.foreground', 'statusBar.background'),
                    @('tab.activeForeground', 'tab.activeBackground'),
                    @('activityBar.foreground', 'activityBar.background'))) {
                $ratio = Get-WtwContrastRatio -Foreground $result[$pair[0]] -Background $result[$pair[1]]
                $ratio | Should -BeGreaterOrEqual 4.5 -Because "$($pair[0]) on $base"
            }
        }
    }

    It 'uses the base color for titleBar.activeBackground' {
        $result = ConvertTo-PeacockColorBlock '#2285a6'
        $result['titleBar.activeBackground'] | Should -Be '#2285a6'
    }

    It 'uses the base color for tab.activeBackground' {
        $result = ConvertTo-PeacockColorBlock '#689b59'
        $result['tab.activeBackground'] | Should -Be '#689b59'
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

Describe 'Get-ContrastForeground' {
    It 'keeps every palette color readable at WCAG AA' {
        # The old YIQ-threshold picked a bucket without checking the result was
        # legible: mid-tone reds, teals and blues landed around 3:1, which is the
        # washed-out chrome text this replaced.
        $palette = @(
            '#e05d44', '#ffa500', '#ffff00', '#008000', '#1a1ad5',
            '#c72391', '#ff0000', '#689b59', '#2285a6', '#007ec6',
            '#b300b3', '#336699', '#000000', '#ffffff'
        )
        foreach ($color in $palette) {
            $fg = Get-ContrastForeground $color
            $ratio = Get-WtwContrastRatio -Foreground $fg -Background $color
            $ratio | Should -BeGreaterThan 4.5 -Because "$color chrome text must stay readable (got $([Math]::Round($ratio,2)):1)"
        }
    }

    It 'escalates to pure black or white when the softened values are not enough' {
        # Pure red reads at only 3.2:1 against #e7e7e7.
        Get-ContrastForeground '#ff0000' | Should -Be '#000000'
        Get-ContrastForeground '#2285a6' | Should -Be '#000000'
    }

    It 'prefers the softened values when they are readable' {
        Get-ContrastForeground '#ffff00' | Should -Be '#15202b'
        Get-ContrastForeground '#1a1ad5' | Should -Be '#e7e7e7'
    }

    It 'accepts a hex value with or without the leading hash' {
        Get-ContrastForeground '#ffff00' | Should -Be (Get-ContrastForeground 'ffff00')
    }
}

Describe 'Get-WtwContrastRatio' {
    It 'matches the WCAG reference values at the extremes' {
        [Math]::Round((Get-WtwContrastRatio -Foreground '#ffffff' -Background '#000000'), 1) | Should -Be 21.0
        [Math]::Round((Get-WtwContrastRatio -Foreground '#ffffff' -Background '#ffffff'), 1) | Should -Be 1.0
    }

    It 'is symmetric' {
        $a = Get-WtwContrastRatio -Foreground '#ff0000' -Background '#ffffff'
        $b = Get-WtwContrastRatio -Foreground '#ffffff' -Background '#ff0000'
        [Math]::Round($a, 4) | Should -Be ([Math]::Round($b, 4))
    }
}

Describe 'Peacock block readability' {
    It 'keeps the active tab distinguishable by more than its fill' {
        # The active tab shares the title bar's hue, so fill alone is a
        # low-contrast cue for "which file am I in".
        $result = ConvertTo-PeacockColorBlock '#2285a6'
        $result.Keys | Should -Contain 'tab.activeBorder'
        $result['tab.activeBorder'] | Should -Be $result['tab.activeForeground']
    }

    It 'keeps the current file visible when the editor loses focus' {
        $result = ConvertTo-PeacockColorBlock '#2285a6'
        $result['tab.unfocusedActiveBackground'] | Should -Be '#2285a6'
        $result['tab.unfocusedActiveForeground'] | Should -Match 'cc$'
    }

    It 'dims chrome text to 80% rather than 60%' {
        $result = ConvertTo-PeacockColorBlock '#e05d44'
        $result['activityBar.inactiveForeground'] | Should -Match 'cc$'
        $result['titleBar.inactiveForeground']    | Should -Match 'cc$'
    }

    It 'contrasts the badge text against the badge, not the base color' {
        $result = ConvertTo-PeacockColorBlock '#ffff00'
        $badgeRatio = Get-WtwContrastRatio -Foreground $result['activityBarBadge.foreground'] -Background $result['activityBarBadge.background']
        $badgeRatio | Should -BeGreaterThan 4.5
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

Describe 'ConvertTo-DarkerHexColor' {
    It 'darkens a color' {
        $result = ConvertTo-DarkerHexColor '#ffffff' -Factor 0.5
        $result | Should -Be '#808080'
    }

    It 'black stays black' {
        $result = ConvertTo-DarkerHexColor '#000000' -Factor 0.5
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
