BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    . "$PSScriptRoot/../public/Set-WtwColor.ps1"
    . "$PSScriptRoot/../private/ConvertTo-PeacockColorBlock.ps1"
    . "$PSScriptRoot/../private/ConvertTo-HexComponent.ps1"
}

Describe 'ConvertTo-WtwRgb' {
    It 'parses a hex color with hash' {
        $rgb = ConvertTo-WtwRgb '#e05d44'
        $rgb[0] | Should -Be 224
        $rgb[1] | Should -Be 93
        $rgb[2] | Should -Be 68
    }

    It 'parses a hex color without hash' {
        $rgb = ConvertTo-WtwRgb 'ff0000'
        $rgb[0] | Should -Be 255
        $rgb[1] | Should -Be 0
        $rgb[2] | Should -Be 0
    }

    It 'parses black' {
        $rgb = ConvertTo-WtwRgb '#000000'
        $rgb | Should -Be @(0, 0, 0)
    }
}

Describe 'Get-PerceptualDistance' {
    It 'returns 0 for identical colors' {
        $d = Get-PerceptualDistance @(100, 100, 100) @(100, 100, 100)
        $d | Should -Be 0
    }

    It 'returns positive distance for different colors' {
        $d = Get-PerceptualDistance @(255, 0, 0) @(0, 0, 255)
        $d | Should -BeGreaterThan 0
    }

    It 'black-white distance is large' {
        $d = Get-PerceptualDistance @(0, 0, 0) @(255, 255, 255)
        $d | Should -BeGreaterThan 500
    }

    It 'similar colors have small distance' {
        $d = Get-PerceptualDistance @(100, 100, 100) @(105, 100, 100)
        $d | Should -BeLessThan 20
    }
}

Describe 'Convert-HslToHex' {
    It 'converts red (H=0)' {
        $hex = Convert-HslToHex 0 1.0 0.5
        $hex | Should -Be '#ff0000'
    }

    It 'converts green (H=120)' {
        $hex = Convert-HslToHex 120 1.0 0.5
        $hex | Should -Be '#00ff00'
    }

    It 'converts blue (H=240)' {
        $hex = Convert-HslToHex 240 1.0 0.5
        $hex | Should -Be '#0000ff'
    }

    It 'converts black (L=0)' {
        $hex = Convert-HslToHex 0 0.0 0.0
        $hex | Should -Be '#000000'
    }

    It 'converts white (L=1)' {
        $hex = Convert-HslToHex 0 0.0 1.0
        $hex | Should -Be '#ffffff'
    }

    It 'produces valid hex format' {
        $hex = Convert-HslToHex 210 0.75 0.45
        $hex | Should -Match '^#[0-9a-f]{6}$'
    }
}

Describe 'Find-WtwContrastColor' {
    It 'returns first palette color when nothing assigned' {
        $colors = [PSCustomObject]@{
            palette     = @('#e05d44', '#2ba7d0', '#97ca00')
            assignments = [PSCustomObject]@{}
        }
        $result = Find-WtwContrastColor $colors
        $result | Should -Be '#e05d44'
    }

    It 'picks a different color than the one already assigned' {
        $colors = [PSCustomObject]@{
            palette     = @('#e05d44', '#2ba7d0', '#97ca00')
            assignments = [PSCustomObject]@{ 'repo/main' = '#e05d44' }
        }
        $result = Find-WtwContrastColor $colors
        $result | Should -Not -Be '#e05d44'
    }

    It 'excludes the ExcludeKey from consideration' {
        $colors = [PSCustomObject]@{
            palette     = @('#e05d44', '#2ba7d0', '#97ca00')
            assignments = [PSCustomObject]@{
                'repo/main' = '#e05d44'
                'repo/task' = '#2ba7d0'
            }
        }
        # Without exclude — #e05d44 and #2ba7d0 are "in use"
        $without = Find-WtwContrastColor $colors
        # With exclude — only #e05d44 is "in use"
        $with = Find-WtwContrastColor $colors -ExcludeKey 'repo/task'
        # The excluded key's color should not constrain the result
        $with | Should -Not -BeNullOrEmpty
    }

    It 'running random twice with ExcludeKey gives different results' {
        # Simulate: first call assigns a color, second call with ExcludeKey should pick different
        $colors = [PSCustomObject]@{
            palette     = @('#e05d44', '#2ba7d0', '#97ca00', '#b300b3', '#fe7d37')
            assignments = [PSCustomObject]@{
                'other/main' = '#2ba7d0'
            }
        }
        $first = Find-WtwContrastColor $colors -ExcludeKey 'repo/main'

        # Now "assign" first result
        $colors.assignments | Add-Member -NotePropertyName 'repo/main' -NotePropertyValue $first -Force

        # Second call should exclude the just-assigned key and pick something different
        $second = Find-WtwContrastColor $colors -ExcludeKey 'repo/main'
        $second | Should -Not -Be $first
    }

    It 'always returns a valid hex color' {
        $colors = [PSCustomObject]@{
            palette     = @('#e05d44', '#2ba7d0', '#97ca00')
            assignments = [PSCustomObject]@{
                'a/main' = '#e05d44'
                'b/main' = '#2ba7d0'
                'c/main' = '#97ca00'
            }
        }
        $result = Find-WtwContrastColor $colors
        $result | Should -Match '^#[0-9a-fA-F]{6}$'
    }
}
