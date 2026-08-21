function Get-WtwInstallInfo {
    <#
    .SYNOPSIS
        Describe how the running copy of wtw got onto this machine.
    .DESCRIPTION
        wtw can be loaded three ways, and the right way to update it differs for
        each one:

          Repo    - imported straight from a source checkout. Updating means
                    `git pull`, not touching the Gallery.
          Manual  - copied into ~/.wtw/module by `wtw install` from a checkout.
                    `Update-Module wtw` does not touch this copy at all, because
                    PowerShellGet never installed it.
          Gallery - the PowerShell Gallery package, either materialised into
                    ~/.wtw/module by `wtw update` or sitting under a PSModulePath
                    entry from Install-Module.

        Telling a manual install to run `Update-Module wtw` is the failure this
        exists to prevent: the command either errors ("not installed by using
        Install-Module") or silently updates a *different* copy that the profile
        loader, the zsh/bash wrappers, and the cmd shim never import — all of
        which name ~/.wtw/module/wtw.psm1 by explicit path.

        `wtw install` records provenance in ~/.wtw/module/INSTALLATION.json;
        installs that predate that file are reported as Manual, which is what
        they are.
    .PARAMETER IncludeGalleryCopies
        Also enumerate wtw modules found on PSModulePath and work out whether one
        of them shadows the loaded copy for a bare `Import-Module wtw`. Skipped by
        default because enumerating PSModulePath is far too slow for the
        per-command update notice.
    .EXAMPLE
        Get-WtwInstallInfo -IncludeGalleryCopies
        Returns the flavour, version, and any shadowing Gallery copies.
    #>
    [CmdletBinding()]
    param(
        [string] $ModuleRoot = $script:WtwModuleRoot,

        [string] $InstallRoot = (Join-Path $HOME '.wtw' 'module'),

        [switch] $IncludeGalleryCopies
    )

    $resolvedRoot = try { [IO.Path]::GetFullPath($ModuleRoot) } catch { $ModuleRoot }
    $resolvedInstall = try { [IO.Path]::GetFullPath($InstallRoot) } catch { $InstallRoot }

    $version = $null
    $manifestPath = Join-Path $resolvedRoot 'wtw.psd1'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try {
            $parsed = $null
            $text = [string](Import-PowerShellDataFile -LiteralPath $manifestPath).ModuleVersion
            if ([version]::TryParse($text, [ref] $parsed)) { $version = $parsed }
        } catch {
            # A manifest we cannot read is reported as an unknown version rather
            # than taking wtw down.
        }
    }

    $record = Read-WtwJsonFile -Path (Join-Path $resolvedRoot 'INSTALLATION.json')

    $isInstallRoot = $resolvedRoot -eq $resolvedInstall
    $flavour = if ($isInstallRoot) {
        $origin = [string](Get-WtwPropertyValue -Object $record -Name 'Origin' -DefaultValue '')
        if ($origin -in @('Gallery', 'Manual')) { $origin } else { 'Manual' }
    } elseif (Test-WtwPathUnderModulePath -Path $resolvedRoot) {
        'Gallery'
    } else {
        'Repo'
    }

    $galleryCopies = @()
    $shadowedBy = $null
    if ($IncludeGalleryCopies) {
        try {
            $galleryCopies = @(
                Get-Module -ListAvailable -Name 'wtw' -ErrorAction SilentlyContinue |
                    Where-Object { [IO.Path]::GetFullPath($_.ModuleBase) -ne $resolvedRoot } |
                    Sort-Object Version -Descending |
                    ForEach-Object {
                        [pscustomobject]@{
                            Version = $_.Version
                            Path    = $_.ModuleBase
                        }
                    }
            )
        } catch {
            $galleryCopies = @()
        }
        # A bare `Import-Module wtw` resolves through PSModulePath, so any copy
        # there wins over ~/.wtw/module no matter which one the shell wrappers
        # load. Worth saying out loud when the versions disagree.
        $shadowedBy = @($galleryCopies | Where-Object { $null -eq $version -or $_.Version -ne $version }) | Select-Object -First 1
    }

    [pscustomobject]@{
        Flavour        = $flavour
        ModuleRoot     = $resolvedRoot
        InstallRoot    = $resolvedInstall
        Version        = $version
        SourcePath     = [string](Get-WtwPropertyValue -Object $record -Name 'SourcePath' -DefaultValue '')
        SourceCommit   = [string](Get-WtwPropertyValue -Object $record -Name 'SourceCommit' -DefaultValue '')
        InstalledAtUtc = ConvertTo-WtwUtcDate -Value (Get-WtwPropertyValue -Object $record -Name 'InstalledAtUtc')
        GalleryCopies  = $galleryCopies
        ShadowedBy     = $shadowedBy
        UpdateCommand  = switch ($flavour) {
            'Repo' { 'git pull && wtw install' }
            default { 'wtw update' }
        }
    }
}

function Test-WtwPathUnderModulePath {
    <#
    .SYNOPSIS
        True when Path sits inside one of the PSModulePath roots.
    .DESCRIPTION
        Used to tell an Install-Module copy apart from a checkout. Compared as
        normalised path prefixes so a trailing separator or a relative entry in
        PSModulePath does not produce a false negative.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $target = try { [IO.Path]::GetFullPath($Path) } catch { return $false }
    $separator = [IO.Path]::DirectorySeparatorChar

    foreach ($entry in @([string]$env:PSModulePath -split [IO.Path]::PathSeparator)) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $root = try { [IO.Path]::GetFullPath($entry) } catch { continue }
        $prefix = $root.TrimEnd($separator, [IO.Path]::AltDirectorySeparatorChar) + $separator
        if ($target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }

    return $false
}
