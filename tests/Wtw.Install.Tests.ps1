BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    . "$PSScriptRoot/../private/Get-WtwPropertyNames.ps1"
    . "$PSScriptRoot/../private/Write-WtwUpdateNotice.ps1"
    . "$PSScriptRoot/../private/Get-WtwInstallInfo.ps1"
    . "$PSScriptRoot/../private/Write-WtwInstallRecord.ps1"

    $script:WtwModuleRoot = (Resolve-Path "$PSScriptRoot/..").Path
    $script:testRoot = Join-Path ([IO.Path]::GetTempPath()) ('wtw-install-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:testRoot -Force | Out-Null

    function New-WtwFakeModule {
        <#
            A directory that looks enough like an installed wtw for
            Get-WtwInstallInfo and Get-Module -ListAvailable.
        #>
        param(
            [string] $Path,
            [string] $Version = '1.2.3',
            [string] $Origin
        )
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $Path 'wtw.psm1') -Value '# fake' -Encoding utf8
        "@{ ModuleVersion = '$Version'; RootModule = 'wtw.psm1'; GUID = '$([guid]::NewGuid())'; Author = 'test' }" |
            Set-Content -LiteralPath (Join-Path $Path 'wtw.psd1') -Encoding utf8
        if ($Origin) {
            Write-WtwInstallRecord -InstallRoot $Path -Origin $Origin -Version $Version -SourcePath '/some/checkout'
        }
        return $Path
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:testRoot) {
        Remove-Item -LiteralPath $script:testRoot -Recurse -Force
    }
}

Describe 'Get-WtwInstallInfo' {
    It 'reports a checkout outside PSModulePath as Repo' {
        $root = New-WtwFakeModule -Path (Join-Path $script:testRoot 'checkout')

        $info = Get-WtwInstallInfo -ModuleRoot $root -InstallRoot (Join-Path $script:testRoot 'nowhere')

        $info.Flavour | Should -Be 'Repo'
        $info.Version | Should -Be ([version]'1.2.3')
        # A checkout is updated with git, not from the Gallery.
        $info.UpdateCommand | Should -Match 'git pull'
    }

    It 'reports an unstamped install root as Manual' {
        # Installs made before INSTALLATION.json existed have no record. Manual is
        # the safe reading: it is what `wtw install` produced.
        $root = New-WtwFakeModule -Path (Join-Path $script:testRoot 'legacy-install')

        $info = Get-WtwInstallInfo -ModuleRoot $root -InstallRoot $root

        $info.Flavour | Should -Be 'Manual'
        $info.UpdateCommand | Should -Be 'wtw update'
    }

    It 'reads the recorded origin when the install is stamped' {
        $root = New-WtwFakeModule -Path (Join-Path $script:testRoot 'gallery-install') -Origin 'Gallery'

        $info = Get-WtwInstallInfo -ModuleRoot $root -InstallRoot $root

        $info.Flavour | Should -Be 'Gallery'
        $info.SourcePath | Should -Be '/some/checkout'
        $info.InstalledAtUtc | Should -Not -BeNullOrEmpty
    }

    It 'treats a module under PSModulePath as a Gallery install' {
        $moduleHome = Join-Path $script:testRoot 'psmodulepath'
        $root = New-WtwFakeModule -Path (Join-Path $moduleHome 'wtw')
        $original = $env:PSModulePath
        try {
            $env:PSModulePath = $moduleHome + [IO.Path]::PathSeparator + $original
            $info = Get-WtwInstallInfo -ModuleRoot $root -InstallRoot (Join-Path $script:testRoot 'nowhere')
            $info.Flavour | Should -Be 'Gallery'
        } finally {
            $env:PSModulePath = $original
        }
    }

    It 'flags a PSModulePath copy that shadows the loaded one' {
        # `Import-Module wtw` resolves through PSModulePath, so a stale
        # Install-Module copy answers for wtw everywhere except the shell
        # wrappers, which name ~/.wtw/module by path.
        $moduleHome = Join-Path $script:testRoot 'shadow-psmodulepath'
        New-WtwFakeModule -Path (Join-Path $moduleHome 'wtw/9.9.9') -Version '9.9.9' | Out-Null
        $loaded = New-WtwFakeModule -Path (Join-Path $script:testRoot 'shadowed-install') -Version '1.2.3'

        $original = $env:PSModulePath
        try {
            $env:PSModulePath = $moduleHome + [IO.Path]::PathSeparator + $original
            $info = Get-WtwInstallInfo -ModuleRoot $loaded -InstallRoot $loaded -IncludeGalleryCopies
        } finally {
            $env:PSModulePath = $original
        }

        $info.ShadowedBy | Should -Not -BeNullOrEmpty
        $info.ShadowedBy.Version | Should -Be ([version]'9.9.9')
    }

    It 'does not enumerate PSModulePath unless asked' {
        # The per-command update notice calls this; enumerating every module root
        # on every wtw command is far too slow.
        $root = New-WtwFakeModule -Path (Join-Path $script:testRoot 'quiet-install')

        $info = Get-WtwInstallInfo -ModuleRoot $root -InstallRoot $root

        $info.GalleryCopies | Should -BeNullOrEmpty
        $info.ShadowedBy | Should -BeNullOrEmpty
    }
}

Describe 'Write-WtwInstallRecord' {
    It 'round-trips origin, version, and source path' {
        $root = Join-Path $script:testRoot 'record'
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        Write-WtwInstallRecord -InstallRoot $root -Origin 'Manual' -Version ([version]'0.2.10') -SourcePath '/repo/wtw'

        $record = Get-Content -LiteralPath (Join-Path $root 'INSTALLATION.json') -Raw | ConvertFrom-Json
        $record.Origin | Should -Be 'Manual'
        $record.Version | Should -Be '0.2.10'
        $record.SourcePath | Should -Be '/repo/wtw'
    }

    It 'never throws when the install root is unwritable' {
        { Write-WtwInstallRecord -InstallRoot (Join-Path $script:testRoot 'does/not/exist') -Origin 'Gallery' -Version '1.0.0' } |
            Should -Not -Throw
    }
}

Describe 'Update-Wtw' {
    It 'reports up to date without downloading when the versions match' {
        InModuleScope wtw {
            Mock Get-WtwInstallInfo { [pscustomobject]@{
                    Flavour = 'Manual'; ModuleRoot = (Join-Path $HOME '.wtw/module')
                    InstallRoot = (Join-Path $HOME '.wtw/module'); Version = [version]'1.0.0'
                    SourcePath = ''; SourceCommit = ''; InstalledAtUtc = $null
                    GalleryCopies = @(); ShadowedBy = $null; UpdateCommand = 'wtw update'
                } }
            Mock Get-WtwUpdateStatus { [pscustomobject]@{
                    CurrentVersion = [version]'1.0.0'; LatestVersion = [version]'1.0.0'
                    UpdateAvailable = $false; Status = 'Available'; CheckedAtUtc = [DateTime]::UtcNow; Source = 'cache'
                } }
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*wtw.psm1' }
            Mock Save-WtwGalleryPackage { }
            Mock Read-Host { 'n' }

            $output = (Update-Wtw 6>&1 | Out-String)

            $output | Should -Match 'Up to date'
            Should -Invoke Save-WtwGalleryPackage -Times 0 -Exactly
            Should -Invoke Read-Host -Times 0 -Exactly
        }
    }

    It 'treats a local build ahead of the Gallery as current, not as a problem' {
        InModuleScope wtw {
            Mock Get-WtwInstallInfo { [pscustomobject]@{
                    Flavour = 'Manual'; ModuleRoot = (Join-Path $HOME '.wtw/module')
                    InstallRoot = (Join-Path $HOME '.wtw/module'); Version = [version]'2.0.0'
                    SourcePath = '/repo/wtw'; SourceCommit = ''; InstalledAtUtc = $null
                    GalleryCopies = @(); ShadowedBy = $null; UpdateCommand = 'wtw update'
                } }
            Mock Get-WtwUpdateStatus { [pscustomobject]@{
                    CurrentVersion = [version]'2.0.0'; LatestVersion = [version]'1.0.0'
                    UpdateAvailable = $false; Status = 'Available'; CheckedAtUtc = [DateTime]::UtcNow; Source = 'cache'
                } }
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*wtw.psm1' }
            Mock Save-WtwGalleryPackage { }

            $output = (Update-Wtw 6>&1 | Out-String)

            $output | Should -Match 'nothing to do'
            $output | Should -Not -Match 'available'
            Should -Invoke Save-WtwGalleryPackage -Times 0 -Exactly
        }
    }

    It 'reports the pending update under --check without downloading it' {
        InModuleScope wtw {
            Mock Get-WtwInstallInfo { [pscustomobject]@{
                    Flavour = 'Manual'; ModuleRoot = (Join-Path $HOME '.wtw/module')
                    InstallRoot = (Join-Path $HOME '.wtw/module'); Version = [version]'1.0.0'
                    SourcePath = ''; SourceCommit = ''; InstalledAtUtc = $null
                    GalleryCopies = @(); ShadowedBy = $null; UpdateCommand = 'wtw update'
                } }
            Mock Get-WtwUpdateStatus { [pscustomobject]@{
                    CurrentVersion = [version]'1.0.0'; LatestVersion = [version]'9.9.9'
                    UpdateAvailable = $true; Status = 'Available'; CheckedAtUtc = [DateTime]::UtcNow; Source = 'cache'
                } }
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*wtw.psm1' }
            Mock Save-WtwGalleryPackage { }
            Mock Read-Host { 'y' }

            $output = (Update-Wtw -Check 6>&1 | Out-String)

            $output | Should -Match 'Update available: 1\.0\.0 -> 9\.9\.9'
            Should -Invoke Save-WtwGalleryPackage -Times 0 -Exactly
            Should -Invoke Read-Host -Times 0 -Exactly
        }
    }

    It 'says a hand-installed copy is being replaced, and stops when declined' {
        InModuleScope wtw {
            Mock Get-WtwInstallInfo { [pscustomobject]@{
                    Flavour = 'Manual'; ModuleRoot = (Join-Path $HOME '.wtw/module')
                    InstallRoot = (Join-Path $HOME '.wtw/module'); Version = [version]'1.0.0'
                    SourcePath = '/repo/wtw'; SourceCommit = ''; InstalledAtUtc = $null
                    GalleryCopies = @(); ShadowedBy = $null; UpdateCommand = 'wtw update'
                } }
            Mock Get-WtwUpdateStatus { [pscustomobject]@{
                    CurrentVersion = [version]'1.0.0'; LatestVersion = [version]'9.9.9'
                    UpdateAvailable = $true; Status = 'Available'; CheckedAtUtc = [DateTime]::UtcNow; Source = 'cache'
                } }
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*wtw.psm1' }
            Mock Save-WtwGalleryPackage { }
            Mock Read-Host { 'n' }

            $output = (Update-Wtw 6>&1 | Out-String)

            $output | Should -Match 'hand-installed from a checkout'
            $output | Should -Match 'Cancelled'
            Should -Invoke Save-WtwGalleryPackage -Times 0 -Exactly
        }
    }

    It 'stays quiet about the Gallery when it cannot be reached' {
        InModuleScope wtw {
            Mock Get-WtwInstallInfo { [pscustomobject]@{
                    Flavour = 'Manual'; ModuleRoot = (Join-Path $HOME '.wtw/module')
                    InstallRoot = (Join-Path $HOME '.wtw/module'); Version = [version]'1.0.0'
                    SourcePath = ''; SourceCommit = ''; InstalledAtUtc = $null
                    GalleryCopies = @(); ShadowedBy = $null; UpdateCommand = 'wtw update'
                } }
            Mock Get-WtwUpdateStatus { [pscustomobject]@{
                    CurrentVersion = [version]'1.0.0'; LatestVersion = $null
                    UpdateAvailable = $false; Status = 'Unavailable'; CheckedAtUtc = [DateTime]::UtcNow; Source = 'cache'
                } }
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*wtw.psm1' }
            Mock Save-WtwGalleryPackage { }

            $output = (Update-Wtw 6>&1 | Out-String)

            $output | Should -Match 'unreachable'
            Should -Invoke Save-WtwGalleryPackage -Times 0 -Exactly
        }
    }
}

Describe 'Invoke-Wtw update dispatch' {
    It 'routes `wtw update` to Update-Wtw, not to the installer' {
        # These were the same command once, which meant `wtw update` from a normal
        # shell hit Install-Wtw's self-install guard and refused to do anything.
        InModuleScope wtw {
            Mock Update-Wtw { }
            Mock Install-Wtw { }
            Mock Write-WtwUpdateNotice { }
            Invoke-Wtw 'update' 6>&1 | Out-Null
            Should -Invoke Update-Wtw -Times 1 -Exactly
            Should -Invoke Install-Wtw -Times 0 -Exactly
        }
    }
}
