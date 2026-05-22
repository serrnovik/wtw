BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Register-WtwTerminalTitle' {
    BeforeEach {
        Remove-Variable -Scope Global -Name _WtwTerminalTitleHookActive -ErrorAction SilentlyContinue
        Remove-Variable -Scope Global -Name _WtwTerminalTitleHookVersion -ErrorAction SilentlyContinue
        Remove-Variable -Scope Global -Name _WtwTerminalTitleState -ErrorAction SilentlyContinue
        Remove-Variable -Scope Global -Name _WtwSessionPrNumber -ErrorAction SilentlyContinue
        Set-Item -Path function:global:prompt -Value { 'base-prompt' }
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
}
