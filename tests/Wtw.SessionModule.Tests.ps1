BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    # Private helpers under test; the module loads them, but these names are not exported.
    . "$PSScriptRoot/../private/Get-WtwInstallInfo.ps1"
    . "$PSScriptRoot/../private/Confirm-WtwSessionModuleCurrent.ps1"

    $script:testRoot = Join-Path ([IO.Path]::GetTempPath()) ('wtw-session-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:testRoot -Force | Out-Null

    function New-WtwFakeModule {
        param(
            [string] $Path,
            [string] $Version = '1.2.3'
        )
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $Path 'wtw.psm1') -Value '# fake' -Encoding utf8
        "@{ ModuleVersion = '$Version'; RootModule = 'wtw.psm1'; GUID = '$([guid]::NewGuid())'; Author = 'test' }" |
            Set-Content -LiteralPath (Join-Path $Path 'wtw.psd1') -Encoding utf8
        return $Path
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:testRoot) {
        Remove-Item -LiteralPath $script:testRoot -Recurse -Force
    }
}

Describe 'Get-WtwManifestVersion' {
    It 'reads ModuleVersion from a sibling manifest' {
        $root = New-WtwFakeModule -Path (Join-Path $script:testRoot 'manifest') -Version '0.2.28'
        Get-WtwManifestVersion -ModuleRoot $root | Should -Be ([version]'0.2.28')
    }

    It 'returns null when the manifest is missing' {
        $root = Join-Path $script:testRoot 'no-manifest'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Get-WtwManifestVersion -ModuleRoot $root | Should -BeNullOrEmpty
    }
}

Describe 'Get-WtwSessionModuleStatus' {
    It 'is not stale when the loaded snapshot matches the files next to it' {
        $loaded = New-WtwFakeModule -Path (Join-Path $script:testRoot 'same') -Version '0.2.28'
        $status = Get-WtwSessionModuleStatus -ModuleRoot $loaded -InstallRoot (Join-Path $script:testRoot 'nowhere') -LoadedVersion ([version]'0.2.28')
        $status.Stale | Should -BeFalse
        $status.Reason | Should -Be 'loaded-root'
        $status.ReloadVersion | Should -Be ([version]'0.2.28')
    }

    It 'is stale when the loaded snapshot is older than the files next to it' {
        $loaded = New-WtwFakeModule -Path (Join-Path $script:testRoot 'inplace') -Version '0.2.28'
        $status = Get-WtwSessionModuleStatus -ModuleRoot $loaded -InstallRoot $loaded -LoadedVersion ([version]'0.2.26')
        $status.Stale | Should -BeTrue
        $status.SameRoot | Should -BeTrue
        $status.ReloadRoot | Should -Be ([IO.Path]::GetFullPath($loaded))
    }

    It 'points ReloadRoot at a newer install than the loaded checkout' {
        $checkout = New-WtwFakeModule -Path (Join-Path $script:testRoot 'checkout-old') -Version '0.2.26'
        $install = New-WtwFakeModule -Path (Join-Path $script:testRoot 'install-new') -Version '0.2.28'
        $status = Get-WtwSessionModuleStatus -ModuleRoot $checkout -InstallRoot $install -LoadedVersion ([version]'0.2.26')
        $status.Stale | Should -BeTrue
        $status.Reason | Should -Be 'install'
        $status.ReloadVersion | Should -Be ([version]'0.2.28')
        $status.ReloadRoot | Should -Be ([IO.Path]::GetFullPath($install))
    }

    It 'does not prefer an older install over a newer checkout' {
        $checkout = New-WtwFakeModule -Path (Join-Path $script:testRoot 'checkout-new') -Version '0.2.28'
        $install = New-WtwFakeModule -Path (Join-Path $script:testRoot 'install-old') -Version '0.2.26'
        $status = Get-WtwSessionModuleStatus -ModuleRoot $checkout -InstallRoot $install -LoadedVersion ([version]'0.2.28')
        $status.Stale | Should -BeFalse
        $status.Reason | Should -Be 'loaded-root'
        $status.ReloadRoot | Should -Be ([IO.Path]::GetFullPath($checkout))
    }

    It 'keeps a checkout when WTW_USE_REPO_MODULE is set even if the install is newer' {
        $checkout = New-WtwFakeModule -Path (Join-Path $script:testRoot 'dev-checkout') -Version '0.2.26'
        $install = New-WtwFakeModule -Path (Join-Path $script:testRoot 'dev-install') -Version '0.2.28'
        $oldValue = $env:WTW_USE_REPO_MODULE
        try {
            $env:WTW_USE_REPO_MODULE = '1'
            $status = Get-WtwSessionModuleStatus -ModuleRoot $checkout -InstallRoot $install -LoadedVersion ([version]'0.2.26')
            $status.UseRepoModule | Should -BeTrue
            $status.Reason | Should -Be 'loaded-root'
            $status.ReloadRoot | Should -Be ([IO.Path]::GetFullPath($checkout))
            $status.Stale | Should -BeFalse
        } finally {
            $env:WTW_USE_REPO_MODULE = $oldValue
        }
    }
}

Describe 'Confirm-WtwSessionModuleCurrent' {
    It 'does not auto-import during a Pester run' {
        InModuleScope wtw {
            Mock Import-WtwSessionModule {}
            Mock Get-Command { throw 'Pester guard should not re-dispatch' }
            Mock Get-WtwSessionModuleStatus {
                [pscustomobject]@{
                    Stale            = $true
                    LoadedRoot       = 'C:\mod'
                    ReloadRoot       = 'C:\mod'
                    ReloadModulePath = 'C:\mod\wtw.psm1'
                    LoadedVersion    = [version]'0.2.26'
                    ReloadVersion    = [version]'0.2.28'
                }
            }

            Confirm-WtwSessionModuleCurrent -OriginalArgs @('list') | Should -BeFalse
            Should -Invoke Import-WtwSessionModule -Times 0 -Exactly
        }
    }

    It 'auto-imports a newer copy of the same module and re-runs the command' {
        InModuleScope wtw {
            $script:reinvoked = $false
            $oldCi = $env:CI
            try {
                # Confirm skips auto-import when $env:CI is set (Woodpecker).
                Remove-Item Env:CI -ErrorAction SilentlyContinue
                Mock Test-WtwIsPesterRun { $false }
                Mock Import-WtwSessionModule {}
                Mock Get-Command { { $script:reinvoked = $true } }
                Mock Test-Path { $true }
                Mock Get-WtwSessionModuleStatus {
                    [pscustomobject]@{
                        Stale            = $true
                        LoadedRoot       = 'C:\mod'
                        ReloadRoot       = 'C:\mod'
                        ReloadModulePath = 'C:\mod\wtw.psm1'
                        LoadedVersion    = [version]'0.2.26'
                        ReloadVersion    = [version]'0.2.28'
                    }
                }

                $did = Confirm-WtwSessionModuleCurrent -OriginalArgs @('list')
                $did | Should -BeTrue
                $script:reinvoked | Should -BeTrue
                Should -Invoke Import-WtwSessionModule -Times 1 -Exactly -ParameterFilter {
                    $ModulePath -eq 'C:\mod\wtw.psm1'
                }
            } finally {
                if ($null -eq $oldCi) {
                    Remove-Item Env:CI -ErrorAction SilentlyContinue
                } else {
                    $env:CI = $oldCi
                }
            }
        }
    }

    It 'does not auto-switch a checkout session to ~/.wtw/module' {
        InModuleScope wtw {
            Mock Test-WtwIsPesterRun { $false }
            Mock Import-WtwSessionModule {}
            Mock Test-Path { $true }
            Mock Get-WtwSessionModuleStatus {
                [pscustomobject]@{
                    Stale            = $true
                    LoadedRoot       = 'C:\checkout'
                    ReloadRoot       = 'C:\Users\me\.wtw\module'
                    ReloadModulePath = 'C:\Users\me\.wtw\module\wtw.psm1'
                    LoadedVersion    = [version]'0.2.26'
                    ReloadVersion    = [version]'0.2.28'
                }
            }

            Confirm-WtwSessionModuleCurrent -OriginalArgs @('wmux') | Should -BeFalse
            Should -Invoke Import-WtwSessionModule -Times 0 -Exactly
        }
    }

    It 'force-imports the preferred copy without re-dispatching' {
        InModuleScope wtw {
            $script:reinvoked = $false
            Mock Import-WtwSessionModule {}
            Mock Get-Command { { $script:reinvoked = $true } }
            Mock Test-Path { $true }
            Mock Get-WtwSessionModuleStatus {
                [pscustomobject]@{
                    Stale            = $true
                    LoadedRoot       = 'C:\checkout'
                    ReloadRoot       = 'C:\Users\me\.wtw\module'
                    ReloadModulePath = 'C:\Users\me\.wtw\module\wtw.psm1'
                    LoadedVersion    = [version]'0.2.26'
                    ReloadVersion    = [version]'0.2.28'
                }
            }

            Confirm-WtwSessionModuleCurrent -Force | Should -BeTrue
            $script:reinvoked | Should -BeFalse
            Should -Invoke Import-WtwSessionModule -Times 1 -Exactly -ParameterFilter {
                $ModulePath -eq 'C:\Users\me\.wtw\module\wtw.psm1'
            }
        }
    }

    It 'honors WTW_NO_SESSION_RELOAD for the automatic check' {
        InModuleScope wtw {
            Mock Import-WtwSessionModule {}
            Mock Test-WtwIsPesterRun { $false }
            Mock Get-WtwSessionModuleStatus { throw 'should not probe when opted out' }
            $oldValue = $env:WTW_NO_SESSION_RELOAD
            try {
                $env:WTW_NO_SESSION_RELOAD = '1'
                Confirm-WtwSessionModuleCurrent -OriginalArgs @('list') | Should -BeFalse
                Should -Invoke Import-WtwSessionModule -Times 0 -Exactly
            } finally {
                $env:WTW_NO_SESSION_RELOAD = $oldValue
            }
        }
    }
}

Describe 'Invoke-Wtw session-reload wiring' {
    It 'checks for a stale session on a normal command' {
        InModuleScope wtw {
            Mock Confirm-WtwSessionModuleCurrent { $false }
            Mock Write-WtwUpdateNotice { }
            Invoke-Wtw 6>&1 | Out-Null
            Should -Invoke Confirm-WtwSessionModuleCurrent -Times 1 -Exactly
        }
    }

    It 'skips the session check for the internal commands the shell wrappers parse' {
        InModuleScope wtw {
            Mock Confirm-WtwSessionModuleCurrent { $false }
            Mock Write-WtwUpdateNotice { }
            Mock Get-WtwRegistry { [pscustomobject]@{ repos = [pscustomobject]@{} } }
            Mock Get-WtwColors { [pscustomobject]@{ assignments = [pscustomobject]@{} } }
            Invoke-Wtw '__aliases' | Out-Null
            Should -Invoke Confirm-WtwSessionModuleCurrent -Times 0 -Exactly
        }
    }

    It 'routes `wtw reload` to Invoke-WtwReloadSession' {
        InModuleScope wtw {
            Mock Invoke-WtwReloadSession { }
            Mock Write-WtwUpdateNotice { }
            Invoke-Wtw 'reload' 6>&1 | Out-Null
            Should -Invoke Invoke-WtwReloadSession -Times 1 -Exactly
        }
    }

    It 'does not auto-confirm when the command is reload' {
        InModuleScope wtw {
            Mock Confirm-WtwSessionModuleCurrent { $false }
            Mock Invoke-WtwReloadSession { }
            Mock Write-WtwUpdateNotice { }
            Invoke-Wtw 'reload' 6>&1 | Out-Null
            Should -Invoke Confirm-WtwSessionModuleCurrent -Times 0 -Exactly
        }
    }
}

Describe 'wtw module load snapshot' {
    It 'records the manifest version of the imported copy' {
        InModuleScope wtw {
            $script:WtwLoadedManifestVersion | Should -Be (Get-WtwManifestVersion -ModuleRoot $script:WtwModuleRoot)
        }
    }
}
