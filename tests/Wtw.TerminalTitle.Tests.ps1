BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Register-WtwTerminalTitle' {
    BeforeEach {
        Remove-Variable -Scope Global -ErrorAction SilentlyContinue -Name `
            _WtwTerminalTitleHookActive, _WtwTerminalTitleHookVersion, _WtwTerminalTitleState,
            _WtwSessionPrNumber, _WtwTitleRepoRoot, _WtwTitleFolderName, _WtwTitleIsAdmin, _WtwTitleLabel
        $script:savedPrompt = (Get-Item function:prompt -ErrorAction SilentlyContinue)?.ScriptBlock
        # Register-WtwTerminalTitle is exported from the module, so its internal
        # calls resolve module-scoped commands — mocks must target -ModuleName wtw.
        Mock Set-WtwTerminalColor {} -ModuleName wtw
    }
    AfterEach {
        if ($script:savedPrompt) { Set-Item -Path function:global:prompt -Value $script:savedPrompt }
    }

    It 'rebinds the active title state on repeated registration' {
        InModuleScope wtw {
            Mock Get-WtwCurrentPrNumber { $null }
            Mock Set-WtwTerminalColor { }
            Mock Get-WtwWindowTitle { "title:$FolderName" }

            $firstRepo = Join-Path ([IO.Path]::GetTempPath()) 'snowmain1'
            $secondRepo = Join-Path ([IO.Path]::GetTempPath()) 'snowmain1_feature'

            Register-WtwTerminalTitle -RepoRoot $firstRepo -TabColor '#111111' | Out-Null
            $firstHook = (Get-Item function:prompt).ScriptBlock.ToString()

            Register-WtwTerminalTitle -RepoRoot $secondRepo -TabColor '#222222' | Out-Null
            $secondHook = (Get-Item function:prompt).ScriptBlock.ToString()

            $global:_WtwTerminalTitleState.RepoRoot | Should -Be $secondRepo
            $global:_WtwTerminalTitleState.FolderName | Should -Be 'snowmain1_feature'
            $secondHook | Should -Be $firstHook -Because 'the existing prompt hook should be reused, not wrapped again'
        }
    }

    It 'migrates a pre-version prompt hook in an existing tab' {
        InModuleScope wtw {
            Mock Get-WtwCurrentPrNumber { $null }
            Mock Set-WtwTerminalColor { }
            Mock Get-WtwWindowTitle { "title:$FolderName" }

            $global:_WtwTerminalTitleHookActive = $true
            Set-Item -Path function:global:prompt -Value { 'old-hook' }
            $oldHook = (Get-Item function:prompt).ScriptBlock.ToString()

            Register-WtwTerminalTitle -RepoRoot (Join-Path ([IO.Path]::GetTempPath()) 'snowmain1_feature') -TabColor '#222222' | Out-Null
            $newHook = (Get-Item function:prompt).ScriptBlock.ToString()

            $global:_WtwTerminalTitleHookVersion | Should -Be 2
            $global:_WtwTerminalTitleState.FolderName | Should -Be 'snowmain1_feature'
            $newHook | Should -Not -Be $oldHook
        }
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

    It 'initializes absent hook globals under strict mode' {
        Mock Get-WtwCurrentPrNumber { $null } -ModuleName wtw

        {
            Set-StrictMode -Version Latest
            Register-WtwTerminalTitle -RepoRoot '/tmp/fresh-strict-session' | Out-Null
        } | Should -Not -Throw

        $global:_WtwTerminalTitleHookActive | Should -BeTrue
        $global:_WtwTerminalTitleHookVersion | Should -Be 2
    }

    It 'builds a title even when the module icon pool is unavailable' {
        InModuleScope wtw {
            Mock Get-WtwIconPool { @() }

            { Get-WtwWindowTitle -RepoRoot '/tmp/snowmain1_stripe' -FolderName 'snowmain1_stripe' } | Should -Not -Throw
            Get-WtwWindowTitle -RepoRoot '/tmp/snowmain1_stripe' -FolderName 'snowmain1_stripe' | Should -Match 'snowmain1_stripe'
        }
    }
}
