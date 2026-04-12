BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Shell wrapper files' {
    It 'wtw.zsh exists and is non-empty' {
        $path = Join-Path $PSScriptRoot '../shell/wtw.zsh'
        $path | Should -Exist
        (Get-Content $path -Raw).Length | Should -BeGreaterThan 100
    }

    It 'wtw.bash exists and is non-empty' {
        $path = Join-Path $PSScriptRoot '../shell/wtw.bash'
        $path | Should -Exist
        (Get-Content $path -Raw).Length | Should -BeGreaterThan 100
    }

    It 'wtw.zsh defines wtw function' {
        $content = Get-Content (Join-Path $PSScriptRoot '../shell/wtw.zsh') -Raw
        $content | Should -Match 'wtw\(\)'
    }

    It 'wtw.bash defines wtw function' {
        $content = Get-Content (Join-Path $PSScriptRoot '../shell/wtw.bash') -Raw
        $content | Should -Match 'wtw\(\)'
    }

    It 'zsh wrapper resolves pwsh path at source time' {
        $content = Get-Content (Join-Path $PSScriptRoot '../shell/wtw.zsh') -Raw
        $content | Should -Match '_wtw_pwsh=\$\(command -v pwsh'
    }

    It 'bash wrapper resolves pwsh path at source time' {
        $content = Get-Content (Join-Path $PSScriptRoot '../shell/wtw.bash') -Raw
        $content | Should -Match '_wtw_pwsh=\$\(command -v pwsh'
    }

    It 'neither wrapper uses bare pwsh for commands (only $_wtw_pwsh)' {
        foreach ($file in @('wtw.zsh', 'wtw.bash')) {
            $lines = Get-Content (Join-Path $PSScriptRoot "../shell/$file")
            foreach ($line in $lines) {
                # Skip comments, the resolver line itself, and the fallback echo
                if ($line -match '^\s*#') { continue }
                if ($line -match '_wtw_pwsh=') { continue }
                if ($line -match 'command -v pwsh') { continue }
                if ($line -match 'echo "pwsh"') { continue }
                if ($line -match '/pwsh') { continue }  # path probing lines
                # No bare 'pwsh ' should appear
                $line | Should -Not -Match '(?<![_$/])\bpwsh\b\s+-No' -Because "line in $file should use `$_wtw_pwsh: $line"
            }
        }
    }
}

Describe 'Terminal escape sequences' {
    It 'Set-WtwTerminalColor does not throw with valid hex color' {
        { Set-WtwTerminalColor -Color '#e05d44' -Title 'test' } | Should -Not -Throw
    }

    It 'Set-WtwTerminalColor does not throw with no color' {
        { Set-WtwTerminalColor -Title 'test-only' } | Should -Not -Throw
    }

    It 'Set-WtwTerminalColor does not throw with empty params' {
        { Set-WtwTerminalColor } | Should -Not -Throw
    }

    It 'Reset-WtwTerminalColor does not throw' {
        { Reset-WtwTerminalColor } | Should -Not -Throw
    }
}

Describe '__resolve and __aliases output format' {
    # These tests validate the output contract that zsh/bash wrappers depend on.
    # They run against the real registry — skip if no repos registered.

    BeforeAll {
        $registry = Get-WtwRegistry
        $script:hasRepos = $registry.repos.PSObject.Properties.Name.Count -gt 0
        if ($script:hasRepos) {
            $script:firstRepo = $registry.repos.PSObject.Properties.Name | Select-Object -First 1
            $script:firstAlias = (Get-WtwRepoAliases $registry.repos.$($script:firstRepo)) | Select-Object -First 1
        }
    }

    It '__aliases outputs tab-separated lines with 5 fields' -Skip:(-not $script:hasRepos) {
        $result = & { Invoke-Wtw __aliases } 6>$null
        $lines = $result -split "`n" | Where-Object { $_.Trim() }
        $lines.Count | Should -BeGreaterThan 0
        foreach ($line in $lines) {
            ($line -split "`t").Count | Should -Be 5 -Because "each alias line needs: name, path, color, title, script"
        }
    }

    It '__resolve returns exactly one line with tab-separated fields' -Skip:(-not $script:hasRepos) {
        $result = & { Invoke-Wtw __resolve $script:firstAlias } 6>$null
        $lines = @($result -split "`n" | Where-Object { $_.Trim() })
        $lines.Count | Should -Be 1
        ($lines[0] -split "`t").Count | Should -BeGreaterOrEqual 3
    }

    It '__resolve output contains no Write-Host noise' -Skip:(-not $script:hasRepos) {
        $result = & { Invoke-Wtw __resolve $script:firstAlias } 6>$null
        $result | Should -Not -Match 'Fuzzy match'
        $result | Should -Not -Match 'Detected'
        $result | Should -Not -Match '\[0m'  # no ANSI escapes
    }
}
