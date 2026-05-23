BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Register-WtwTerminalTitle' {
    BeforeEach {
        Remove-Variable -Scope Global -ErrorAction SilentlyContinue -Name `
            _WtwTerminalTitleHookActive, _WtwSessionPrNumber, _WtwTitleRepoRoot,
            _WtwTitleFolderName, _WtwTitleIsAdmin, _WtwTitleLabel
        $script:savedPrompt = (Get-Item function:prompt -ErrorAction SilentlyContinue)?.ScriptBlock
        # Register-WtwTerminalTitle is exported from the module, so its internal
        # calls resolve module-scoped commands — mocks must target -ModuleName wtw.
        Mock Set-WtwTerminalColor {} -ModuleName wtw
    }
    AfterEach {
        if ($script:savedPrompt) { Set-Item -Path function:global:prompt -Value $script:savedPrompt }
    }

    It 'refreshes PR and folder when switching worktrees within one session' {
        # Globals (not $script:) so the -ModuleName mock body can reach them.
        $global:prQueue = [System.Collections.Queue]::new(@('63', '83'))
        Mock Get-WtwCurrentPrNumber { $global:prQueue.Dequeue() } -ModuleName wtw

        Register-WtwTerminalTitle -RepoRoot '/tmp/snowmain1_002-stripe-storage-adapter' | Out-Null
        $global:_WtwSessionPrNumber | Should -Be '63'
        $global:_WtwTitleFolderName | Should -Be 'snowmain1_002-stripe-storage-adapter'

        Register-WtwTerminalTitle -RepoRoot '/tmp/snowmain1_NTB-035P2-Generic-primitives' | Out-Null
        $global:_WtwSessionPrNumber | Should -Be '83'
        $global:_WtwTitleFolderName | Should -Be 'snowmain1_NTB-035P2-Generic-primitives'
    }

    It 'applies a title reflecting the latest worktree on re-entry' {
        $global:prQueue = [System.Collections.Queue]::new(@('63', '83'))
        Mock Get-WtwCurrentPrNumber { $global:prQueue.Dequeue() } -ModuleName wtw
        $global:capturedTitles = [System.Collections.Generic.List[string]]::new()
        Mock Set-WtwTerminalColor { $global:capturedTitles.Add($Title) } -ModuleName wtw

        Register-WtwTerminalTitle -RepoRoot '/tmp/snowmain1_002-stripe-storage-adapter' | Out-Null
        Register-WtwTerminalTitle -RepoRoot '/tmp/snowmain1_NTB-035P2-Generic-primitives' | Out-Null

        $global:capturedTitles[-1] | Should -BeLike '*#83*'
        $global:capturedTitles[-1] | Should -BeLike '*NTB-035P2-Generic-primitives*'
    }

    It 'installs the per-prompt hook only once' {
        Mock Get-WtwCurrentPrNumber { '1' } -ModuleName wtw

        Register-WtwTerminalTitle -RepoRoot '/tmp/a' | Out-Null
        $first = (Get-Item function:prompt).ScriptBlock.ToString()
        Register-WtwTerminalTitle -RepoRoot '/tmp/b' | Out-Null
        $second = (Get-Item function:prompt).ScriptBlock.ToString()

        $second | Should -Be $first
    }
}
