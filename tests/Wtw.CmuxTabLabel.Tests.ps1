BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Get-WtwCmuxTabLabel' {
    It 'prefixes the default console+tree icon before the pretty name' {
        Get-WtwCmuxTabLabel -PrettyName 'PF-018' -Icon '🖥️🌳' | Should -Be '🖥️🌳 PF-018'
    }

    It 'trims surrounding whitespace from the pretty name' {
        Get-WtwCmuxTabLabel -PrettyName '  Blue Feature  ' -Icon '🖥️🌳' | Should -Be '🖥️🌳 Blue Feature'
    }

    It 'returns just the icon when the pretty name is blank' {
        Get-WtwCmuxTabLabel -PrettyName '' -Icon '🖥️🌳' | Should -Be '🖥️🌳'
    }

    It 'honors an explicit icon override' {
        Get-WtwCmuxTabLabel -PrettyName 'x' -Icon '🌴' | Should -Be '🌴 x'
    }

    It 'honors $env:WTW_TAB_ICON when no icon is passed' {
        $saved = $env:WTW_TAB_ICON
        try {
            $env:WTW_TAB_ICON = '🚀'
            Get-WtwCmuxTabLabel -PrettyName 'y' | Should -Be '🚀 y'
        } finally {
            $env:WTW_TAB_ICON = $saved
        }
    }

    It 'defaults to the console+tree icon when nothing is set' {
        $saved = $env:WTW_TAB_ICON
        try {
            $env:WTW_TAB_ICON = $null
            Get-WtwCmuxTabLabel -PrettyName 'z' | Should -Be '🖥️🌳 z'
        } finally {
            $env:WTW_TAB_ICON = $saved
        }
    }
}
