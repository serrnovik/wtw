BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    # The notice helpers are private; dot-source them plus the strict-mode-safe
    # property reader they depend on.
    . "$PSScriptRoot/../private/Get-WtwPropertyNames.ps1"
    . "$PSScriptRoot/../private/Write-WtwUpdateNotice.ps1"
    # The notice picks its update command from how wtw was installed.
    . "$PSScriptRoot/../private/Get-WtwInstallInfo.ps1"

    $script:WtwModuleRoot = (Resolve-Path "$PSScriptRoot/..").Path
    $script:testRoot = Join-Path ([IO.Path]::GetTempPath()) ('wtw-update-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:testRoot -Force | Out-Null

    function New-WtwTestCache {
        param(
            [string] $LatestVersion = '99.0.0',
            [string] $Status = 'Available',
            [TimeSpan] $Age = [TimeSpan]::Zero
        )
        $path = Join-Path $script:testRoot ('cache-' + [guid]::NewGuid().ToString('N') + '.json')
        [ordered]@{
            CheckedAtUtc  = ([DateTime]::UtcNow - $Age).ToString('O')
            LatestVersion = $LatestVersion
            Status        = $Status
        } | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding utf8
        return $path
    }

    function Get-WtwTestNotice {
        param([string] $CachePath, [string] $StatePath)
        return (& { Write-WtwUpdateNotice -CachePath $CachePath -StatePath $StatePath -Force } 6>&1 | Out-String)
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:testRoot) {
        Remove-Item -LiteralPath $script:testRoot -Recurse -Force
    }
    Remove-Item Env:WTW_SHELL_SESSION -ErrorAction SilentlyContinue
}

Describe 'Write-WtwUpdateNotice' {
    It 'announces a newer published version once per shell session' {
        $env:WTW_SHELL_SESSION = 'test-once'
        $cache = New-WtwTestCache
        $state = Join-Path $script:testRoot 'state-once.json'

        $first = Get-WtwTestNotice -CachePath $cache -StatePath $state
        $second = Get-WtwTestNotice -CachePath $cache -StatePath $state

        $first | Should -Match 'wtw 99\.0\.0 is available'
        # Running from a checkout: git, not the Gallery.
        $first | Should -Match 'git pull, then wtw install'
        $second | Should -BeNullOrEmpty
    }

    It 'announces again in a different shell session' {
        $cache = New-WtwTestCache
        $state = Join-Path $script:testRoot 'state-sessions.json'

        $env:WTW_SHELL_SESSION = 'session-a'
        Get-WtwTestNotice -CachePath $cache -StatePath $state | Should -Match 'is available'
        $env:WTW_SHELL_SESSION = 'session-b'
        Get-WtwTestNotice -CachePath $cache -StatePath $state | Should -Match 'is available'
    }

    It 'stays silent when the published version is not newer' {
        $env:WTW_SHELL_SESSION = 'test-older'
        $cache = New-WtwTestCache -LatestVersion '0.0.1'
        $state = Join-Path $script:testRoot 'state-older.json'

        Get-WtwTestNotice -CachePath $cache -StatePath $state | Should -BeNullOrEmpty
    }

    It 'stays silent when the last Gallery lookup failed' {
        $env:WTW_SHELL_SESSION = 'test-unavailable'
        $cache = New-WtwTestCache -Status 'Unavailable'
        $state = Join-Path $script:testRoot 'state-unavailable.json'

        Get-WtwTestNotice -CachePath $cache -StatePath $state | Should -BeNullOrEmpty
    }

    It 'stays silent - and does not throw - on a corrupt cache' {
        $env:WTW_SHELL_SESSION = 'test-corrupt'
        $cache = Join-Path $script:testRoot 'corrupt.json'
        Set-Content -LiteralPath $cache -Value 'not json {{' -Encoding utf8
        $state = Join-Path $script:testRoot 'state-corrupt.json'

        { Write-WtwUpdateNotice -CachePath $cache -StatePath $state -Force } | Should -Not -Throw
        Get-WtwTestNotice -CachePath $cache -StatePath $state | Should -BeNullOrEmpty
    }

    It 'never waits on the network: a stale cache prints nothing and returns fast' {
        $env:WTW_SHELL_SESSION = 'test-stale'
        $cache = New-WtwTestCache -Age ([TimeSpan]::FromDays(30))
        $state = Join-Path $script:testRoot 'state-stale.json'

        $elapsed = Measure-Command {
            $script:staleOutput = Get-WtwTestNotice -CachePath $cache -StatePath $state
        }

        $script:staleOutput | Should -BeNullOrEmpty
        $elapsed.TotalSeconds | Should -BeLessThan 2
        # The refresh cooldown stamp proves the check was handed to a detached
        # process instead of being awaited here.
        (Get-Content -LiteralPath $state -Raw | ConvertFrom-Json).LastRefreshSpawnUtc |
            Should -Not -BeNullOrEmpty
    }

    It 'honors the WTW_NO_UPDATE_NOTICE opt-out' {
        $env:WTW_SHELL_SESSION = 'test-optout'
        $cache = New-WtwTestCache
        $state = Join-Path $script:testRoot 'state-optout.json'
        $env:WTW_NO_UPDATE_NOTICE = '1'
        try {
            $output = (& { Write-WtwUpdateNotice -CachePath $cache -StatePath $state } 6>&1 | Out-String)
        } finally {
            Remove-Item Env:WTW_NO_UPDATE_NOTICE -ErrorAction SilentlyContinue
        }

        $output | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-Wtw update-notice wiring' {
    It 'emits the notice for a normal command' {
        InModuleScope wtw {
            Mock Write-WtwUpdateNotice { }
            Invoke-Wtw 6>&1 | Out-Null
            Should -Invoke Write-WtwUpdateNotice -Times 1 -Exactly
        }
    }

    It 'skips the notice for the internal commands the shell wrappers parse' {
        InModuleScope wtw {
            Mock Write-WtwUpdateNotice { }
            Mock Get-WtwRegistry { [pscustomobject]@{ repos = [pscustomobject]@{} } }
            Mock Get-WtwColors { [pscustomobject]@{ assignments = [pscustomobject]@{} } }
            Invoke-Wtw '__aliases' | Out-Null
            Should -Invoke Write-WtwUpdateNotice -Times 0 -Exactly
        }
    }
}

Describe 'Write-WtwUpdateNotice install flavours' {
    It 'points a hand-installed copy at `wtw update`, not at Update-Module' {
        # Update-Module only knows about copies PowerShellGet installed. Aimed at
        # ~/.wtw/module it either errors or updates a copy no loader imports.
        $env:WTW_SHELL_SESSION = 'test-manual-flavour'
        $cache = New-WtwTestCache
        $state = Join-Path $script:testRoot 'state-manual.json'

        $output = InModuleScope wtw -Parameters @{ Cache = $cache; State = $state } {
            param($Cache, $State)
            Mock Get-WtwInstallInfo { [pscustomobject]@{ Flavour = 'Manual'; ModuleRoot = '/x'; UpdateCommand = 'wtw update' } }
            (& { Write-WtwUpdateNotice -CachePath $Cache -StatePath $State -Force } 6>&1 | Out-String)
        }

        $output | Should -Match 'wtw update'
        $output | Should -Not -Match 'Update-Module'
    }

    It 'still announces the version when install detection fails' {
        $env:WTW_SHELL_SESSION = 'test-broken-probe'
        $cache = New-WtwTestCache
        $state = Join-Path $script:testRoot 'state-broken.json'

        $output = InModuleScope wtw -Parameters @{ Cache = $cache; State = $state } {
            param($Cache, $State)
            Mock Get-WtwInstallInfo { throw 'probe exploded' }
            (& { Write-WtwUpdateNotice -CachePath $Cache -StatePath $State -Force } 6>&1 | Out-String)
        }

        $output | Should -Match 'wtw 99\.0\.0 is available'
    }
}

Describe 'Get-WtwUpdateStatus' {
    It 'reports from cache without contacting the Gallery' {
        $cache = New-WtwTestCache -LatestVersion '99.0.0'

        $status = Get-WtwUpdateStatus -CachePath $cache

        $status.Source | Should -Be 'cache'
        $status.LatestVersion | Should -Be ([version]'99.0.0')
        $status.UpdateAvailable | Should -BeTrue
    }
}
