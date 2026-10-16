BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Open-WtwWaveProject' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-wave-" + [guid]::NewGuid())
        $script:projectPath = Join-Path $script:tempDir 'repo_feature'
        New-Item -ItemType Directory -Path $script:projectPath -Force | Out-Null
        $script:wshCalls = [System.Collections.Generic.List[string]]::new()
        $script:blocksJson = '[]'
        $script:savedTabId = $env:WAVETERM_TABID
        $env:WAVETERM_TABID = 'tab-1'

        Mock Get-WtwWshExe { '/usr/bin/wsh' }
        Mock Test-WtwWaveSession { $true }
        Mock Invoke-WtwWshCommand {
            $script:wshCalls.Add(($ArgumentList -join ' '))
            switch ($ArgumentList[0]) {
                'blocks' { return [PSCustomObject]@{ ExitCode = 0; Output = $script:blocksJson } }
                'term' {
                    return [PSCustomObject]@{
                        ExitCode = 0
                        Output   = 'terminal block created: block:11111111-2222-3333-4444-555555555555'
                    }
                }
                default { return [PSCustomObject]@{ ExitCode = 0; Output = '' } }
            }
        }
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:tempDir -ErrorAction SilentlyContinue
        $env:WAVETERM_TABID = $script:savedTabId
    }

    It 'opens a new terminal block at the worktree and titles it' {
        $result = Open-WtwWaveProject -ProjectPath $script:projectPath -PrettyName 'Blue Feature' -Color '#336699'

        $result.Success | Should -BeTrue
        $result.Created | Should -BeTrue
        $result.Id | Should -Be 'block:11111111-2222-3333-4444-555555555555'
        $script:wshCalls | Should -Contain "term $([System.IO.Path]::GetFullPath($script:projectPath))"
        $setmeta = $script:wshCalls | Where-Object { $_ -like 'setmeta *' } | Select-Object -First 1
        $setmeta | Should -Match 'frame:title=Blue Feature'
        $setmeta | Should -Match 'frame:bordercolor=#336699'
    }

    It 'focuses the block already rooted at the worktree instead of splitting again' {
        $full = [System.IO.Path]::GetFullPath($script:projectPath)
        $script:blocksJson = ConvertTo-Json -Depth 5 @(
            [ordered]@{ blockid = 'other'; view = 'term'; meta = @{ 'cmd:cwd' = $script:tempDir } },
            [ordered]@{ blockid = 'match'; view = 'term'; meta = @{ 'cmd:cwd' = $full } }
        )

        $result = Open-WtwWaveProject -ProjectPath $script:projectPath -PrettyName 'Blue Feature'

        $result.Created | Should -BeFalse
        $result.Id | Should -Be 'match'
        $script:wshCalls | Should -Contain 'blocks list --view=term --tab=tab-1 --json'
        @($script:wshCalls | Where-Object { $_ -like 'term *' }).Count | Should -Be 0
        $script:wshCalls | Should -Contain 'focusblock -b match'
    }

    It 'refuses outside a Wave terminal without calling wsh' {
        Mock Test-WtwWaveSession { $false }

        $result = Open-WtwWaveProject -ProjectPath $script:projectPath -PrettyName 'Blue Feature'

        $result.Success | Should -BeFalse
        $result.Reason | Should -Match 'Wave terminal'
        $script:wshCalls.Count | Should -Be 0
    }
}

Describe 'Test-WtwWaveSession' {
    It 'needs both a Wave token and a tab id' {
        $saved = @{ JWT = $env:WAVETERM_JWT; SWAP = $env:WAVETERM_SWAPTOKEN; TAB = $env:WAVETERM_TABID }
        try {
            $env:WAVETERM_JWT = 'jwt'
            Remove-Item Env:WAVETERM_SWAPTOKEN -ErrorAction SilentlyContinue
            Remove-Item Env:WAVETERM_TABID -ErrorAction SilentlyContinue
            Test-WtwWaveSession | Should -BeFalse

            $env:WAVETERM_TABID = 'tab'
            Test-WtwWaveSession | Should -BeTrue
        } finally {
            $env:WAVETERM_JWT = $saved.JWT
            $env:WAVETERM_SWAPTOKEN = $saved.SWAP
            $env:WAVETERM_TABID = $saved.TAB
        }
    }
}
