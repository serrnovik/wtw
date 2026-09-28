BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'Invoke-WtwDirectorySwitch' {
    BeforeEach {
        $script:root = Join-Path ([IO.Path]::GetTempPath()) ('wtw-dirswitch-' + [guid]::NewGuid().ToString('N'))
        $script:other = Join-Path ([IO.Path]::GetTempPath()) ('wtw-dirswitch-other-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:root, $script:other | Out-Null
        $script:marker = Join-Path $script:root 'ran.txt'
        $script:gitRepoLog = Join-Path $script:root 'gitrepo.txt'
        $script:previous = Get-Location
        $env:WTW_TEST_MARKER = $script:marker
        $env:WTW_TEST_GITREPO_LOG = $script:gitRepoLog
        function global:Set-GitRepo {
            param($gitRoot, $toolName)
            Set-Content -LiteralPath $env:WTW_TEST_GITREPO_LOG -Value ("{0}|{1}" -f $gitRoot, $toolName)
        }
    }

    AfterEach {
        Set-Location -LiteralPath $script:previous.Path
        Remove-Item -Path function:Set-GitRepo -ErrorAction SilentlyContinue
        Remove-Item -Path alias:wtwTestNa -ErrorAction SilentlyContinue
        Remove-Item -Path Env:WTW_TEST_MARKER, Env:WTW_TEST_GITREPO_LOG -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:root, $script:other -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'runs the configured session script when the shell is already in the directory' {
        @'
Set-Content -LiteralPath $env:WTW_TEST_MARKER -Value ran
Set-Alias -Name wtwTestNa -Value Get-Date -Scope Global -Force
'@ | Set-Content -LiteralPath (Join-Path $script:root 'start-repository-session.ps1')

        Set-Location -LiteralPath $script:root
        $ran = InModuleScope wtw -Parameters @{ TargetPath = $script:root; SessionScript = 'start-repository-session.ps1' } {
            param($TargetPath, $SessionScript)
            Invoke-WtwDirectorySwitch -Path $TargetPath -SessionScript $SessionScript
            $script:WtwSessionScriptRan
        }

        $ran | Should -BeTrue
        Get-Content -LiteralPath $script:marker | Should -Be 'ran'
        Test-Path -LiteralPath $script:gitRepoLog | Should -BeFalse
        Get-Alias wtwTestNa -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'runs a discovered session script when already in the directory and none is configured' {
        @'
Set-Content -LiteralPath $env:WTW_TEST_MARKER -Value discovered
'@ | Set-Content -LiteralPath (Join-Path $script:root 'start-repository-session.ps1')

        Set-Location -LiteralPath $script:root
        $ran = InModuleScope wtw -Parameters @{ TargetPath = $script:root } {
            param($TargetPath)
            Invoke-WtwDirectorySwitch -Path $TargetPath -SessionScript ''
            $script:WtwSessionScriptRan
        }

        $ran | Should -BeTrue
        Get-Content -LiteralPath $script:marker | Should -Be 'discovered'
        Test-Path -LiteralPath $script:gitRepoLog | Should -BeFalse
    }

    It 'does not call Set-GitRepo or throw when already in a directory with no session script' {
        Set-Location -LiteralPath $script:root
        $ran = InModuleScope wtw -Parameters @{ TargetPath = $script:root } {
            param($TargetPath)
            Invoke-WtwDirectorySwitch -Path $TargetPath -SessionScript ''
            $script:WtwSessionScriptRan
        }

        $ran | Should -BeFalse
        Test-Path -LiteralPath $script:gitRepoLog | Should -BeFalse
    }

    It 'still delegates to Set-GitRepo when the shell is not already in the directory' {
        Set-Location -LiteralPath $script:other
        $ran = InModuleScope wtw -Parameters @{ TargetPath = $script:root; SessionScript = 'start-repository-session.ps1' } {
            param($TargetPath, $SessionScript)
            Invoke-WtwDirectorySwitch -Path $TargetPath -SessionScript $SessionScript
            $script:WtwSessionScriptRan
        }

        $ran | Should -BeTrue
        $logged = Get-Content -LiteralPath $script:gitRepoLog -Raw
        $logged.Trim() | Should -Be ("{0}|{1}" -f $script:root, 'start-repository-session.ps1')
        (Get-Location).ProviderPath | Should -Be ((Get-Item -LiteralPath $script:other).FullName)
    }

    It 'changes directory and runs the session script when Set-GitRepo is absent' {
        Remove-Item -Path function:Set-GitRepo -ErrorAction SilentlyContinue
        @'
Set-Content -LiteralPath $env:WTW_TEST_MARKER -Value switched
'@ | Set-Content -LiteralPath (Join-Path $script:root 'start-repository-session.ps1')

        Set-Location -LiteralPath $script:other
        $ran = InModuleScope wtw -Parameters @{ TargetPath = $script:root; SessionScript = 'start-repository-session.ps1' } {
            param($TargetPath, $SessionScript)
            Invoke-WtwDirectorySwitch -Path $TargetPath -SessionScript $SessionScript
            $script:WtwSessionScriptRan
        }

        $ran | Should -BeTrue
        Get-Content -LiteralPath $script:marker | Should -Be 'switched'
        (Get-Location).ProviderPath | Should -Be ((Get-Item -LiteralPath $script:root).FullName)
    }
}
