BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

# Shell wrapper file checks (syntax, function defs, bare-pwsh) are in bats tests.
# This file tests the PowerShell side that the shell wrappers depend on.

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

Describe 'CLI command names for shell wrappers' {
    It 'includes the commands zsh used to swallow as implicit go' {
        $names = @(Get-WtwCliCommandNames)
        foreach ($name in @('info', 'show', 'host', 'agent', 'chatgpt', 'cgpt', 'sbx', 'ss', 'run', 'connect', 'conn', 'ssh', 'superset', 'supersetsh')) {
            $names | Should -Contain $name
        }
    }

    It 'includes every VS Code family prefix' {
        $names = @(Get-WtwCliCommandNames)
        foreach ($member in Get-WtwEditorFamily) {
            foreach ($prefix in @($member.Prefixes)) {
                $names | Should -Contain $prefix
            }
        }
    }

    It 'lists go for the full CLI but not for wrapper passthrough' {
        @(Get-WtwCliCommandNames) | Should -Contain 'go'
        @(Get-WtwCliPassthroughCommandNames) | Should -Not -Contain 'go'
    }

    It 'keeps mutating commands inside the passthrough set' {
        $passthrough = @(Get-WtwCliPassthroughCommandNames)
        foreach ($name in @(Get-WtwCliMutatingCommandNames)) {
            $passthrough | Should -Contain $name
        }
    }

    It '__commands prints one name per line matching Get-WtwCliCommandNames' {
        $expected = @(Get-WtwCliCommandNames)
        $result = @(& { Invoke-Wtw __commands } 6>$null | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        $result | Should -Be $expected
    }

    It '__shell_state emits command, host, and alias markers' {
        $errors = [System.Collections.Generic.List[string]]::new()
        $result = @(& { Invoke-Wtw __shell_state --shell zsh } 6>$null 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $errors.Add("$_")
                return
            }
            "$_"
        })
        $errors | Should -BeNullOrEmpty
        $joined = $result -join "`n"
        $joined | Should -Match '#wtw-commands'
        $joined | Should -Match '#wtw-hosts'
        $joined | Should -Match '#wtw-aliases'
        $joined | Should -Match '(?m)^info$'
        $joined | Should -Match '(?m)^chatgpt$'
        $joined | Should -Not -Match 'Could not resolve'
    }

    It 'zsh/bash/cmd hardcoded lists include every passthrough command as a whole token' {
        $root = Join-Path $PSScriptRoot '..'
        $zsh = Get-Content -LiteralPath (Join-Path $root 'shell/wtw.zsh') -Raw
        $bash = Get-Content -LiteralPath (Join-Path $root 'shell/wtw.bash') -Raw
        $cmd = Get-Content -LiteralPath (Join-Path $root 'shell/wtw.cmd') -Raw

        $zshMatch = [regex]::Match($zsh, '_wtw_passthrough_commands=\((?<body>[\s\S]*?)\)')
        $bashMatch = [regex]::Match($bash, '_wtw_passthrough_commands=\((?<body>[\s\S]*?)\)')
        $cmdMatch = [regex]::Match($cmd, 'set "_NOCD=(?<body>[^"]*)"')
        $zshMatch.Success | Should -BeTrue
        $bashMatch.Success | Should -BeTrue
        $cmdMatch.Success | Should -BeTrue

        $zshTokens = @($zshMatch.Groups['body'].Value -split '\s+' | Where-Object { $_ })
        $bashTokens = @($bashMatch.Groups['body'].Value -split '\s+' | Where-Object { $_ })
        $cmdTokens = @($cmdMatch.Groups['body'].Value -split '\s+' | Where-Object { $_ })

        $zshTokens | Should -Not -Contain 'go'
        $bashTokens | Should -Not -Contain 'go'
        $cmdTokens | Should -Not -Contain 'go'

        foreach ($name in @(Get-WtwCliPassthroughCommandNames)) {
            $zshTokens | Should -Contain $name -Because "wtw.zsh passthrough must include $name (not a substring of copy/code)"
            $bashTokens | Should -Contain $name -Because "wtw.bash passthrough must include $name"
            $cmdTokens | Should -Contain $name -Because "wtw.cmd _NOCD must include $name"
        }
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
        $result | Should -Not -Match 'Substring match'
        $result | Should -Not -Match 'Detected'
        $result | Should -Not -Match '\[0m'  # no ANSI escapes
    }
}
