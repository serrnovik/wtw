BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'Get-WtwShellTheme' {
    BeforeEach {
        $script:savedThemeEnv = @{
            WTW_THEME          = $env:WTW_THEME
            AGENT_SHELL_THEME  = $env:AGENT_SHELL_THEME
            STARSHIP_THEME     = $env:STARSHIP_THEME
            TERM_BACKGROUND    = $env:TERM_BACKGROUND
            COLORFGBG          = $env:COLORFGBG
            NO_COLOR           = $env:NO_COLOR
        }
        $env:WTW_THEME = $null
        $env:AGENT_SHELL_THEME = $null
        $env:STARSHIP_THEME = $null
        $env:TERM_BACKGROUND = $null
        $env:COLORFGBG = $null
        $env:NO_COLOR = $null
    }

    AfterEach {
        foreach ($name in $script:savedThemeEnv.Keys) {
            Set-Item -Path "Env:$name" -Value $script:savedThemeEnv[$name]
        }
    }

    It 'prefers WTW_THEME over AGENT_SHELL_THEME' {
        InModuleScope wtw {
            $env:AGENT_SHELL_THEME = 'dark'
            $env:WTW_THEME = 'light'
            Get-WtwShellTheme | Should -Be 'light'
        }
    }

    It 'follows AGENT_SHELL_THEME from shell-theme' {
        InModuleScope wtw {
            $env:AGENT_SHELL_THEME = 'light'
            Get-WtwShellTheme | Should -Be 'light'
            $env:AGENT_SHELL_THEME = 'dark'
            Get-WtwShellTheme | Should -Be 'dark'
        }
    }

    It 'maps light Yellow to amber ink, not the bright dark-theme yellow' {
        InModuleScope wtw {
            $light = Get-WtwThemeRgb -Color Yellow -Theme light
            $dark = Get-WtwThemeRgb -Color Yellow -Theme dark
            "$($light.R),$($light.G),$($light.B)" | Should -Be '160,90,0'
            "$($dark.R),$($dark.G),$($dark.B)" | Should -Be '251,191,36'
            $lightAnsi = Get-WtwThemeAnsi -ForegroundColor Yellow -Theme light
            $darkAnsi = Get-WtwThemeAnsi -ForegroundColor Yellow -Theme dark
            $lightAnsi | Should -Be "`e[38;2;160;90;0m"
            $darkAnsi | Should -Be "`e[38;2;251;191;36m"
        }
    }

    It 'maps light Cyan and DarkGray to the same inks as agent-shell PSStyle' {
        InModuleScope wtw {
            $cyan = Get-WtwThemeRgb -Color Cyan -Theme light
            $muted = Get-WtwThemeRgb -Color DarkGray -Theme light
            "$($cyan.R),$($cyan.G),$($cyan.B)" | Should -Be '0,80,160'
            "$($muted.R),$($muted.G),$($muted.B)" | Should -Be '80,80,80'
        }
    }
}

Describe 'Write-WtwHost' {
    BeforeEach {
        $script:savedThemeEnv = @{
            WTW_THEME         = $env:WTW_THEME
            AGENT_SHELL_THEME = $env:AGENT_SHELL_THEME
            NO_COLOR          = $env:NO_COLOR
        }
        $env:WTW_THEME = $null
        $env:NO_COLOR = $null
    }

    AfterEach {
        foreach ($name in $script:savedThemeEnv.Keys) {
            Set-Item -Path "Env:$name" -Value $script:savedThemeEnv[$name]
        }
    }

    It 'paints with theme truecolor and never passes ConsoleColor to Write-Host' {
        InModuleScope wtw {
            $env:AGENT_SHELL_THEME = 'light'
            Mock Write-Host { }
            Write-WtwHost '  Clean what?' -ForegroundColor Yellow
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {
                "$Object" -match 'Clean what' -and
                "$Object" -match '38;2;160;90;0' -and
                -not $PSBoundParameters.ContainsKey('ForegroundColor')
            }
        }
    }

    It 'skips ANSI when NO_COLOR is set' {
        $output = InModuleScope wtw {
            $env:AGENT_SHELL_THEME = 'light'
            $env:NO_COLOR = '1'
            Write-WtwHost '  Clean what?' -ForegroundColor Yellow 6>&1 | Out-String
        }
        $output | Should -Match 'Clean what'
        $output | Should -Not -Match '38;2;'
    }
}
