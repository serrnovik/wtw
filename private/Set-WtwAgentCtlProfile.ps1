function Ensure-WtwAgentCtlConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSObject] $Config
    )

    if (-not ($Config.PSObject.Properties.Name -contains 'agentctl') -or -not $Config.agentctl) {
        $Config | Add-Member -NotePropertyName 'agentctl' -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    if (-not ($Config.agentctl.PSObject.Properties.Name -contains 'enabled')) {
        $Config.agentctl | Add-Member -NotePropertyName 'enabled' -NotePropertyValue $true -Force
    }
    if (-not ($Config.agentctl.PSObject.Properties.Name -contains 'defaultProfile') -or [string]::IsNullOrWhiteSpace($Config.agentctl.defaultProfile)) {
        $Config.agentctl | Add-Member -NotePropertyName 'defaultProfile' -NotePropertyValue 'team' -Force
    }
    if (-not ($Config.agentctl.PSObject.Properties.Name -contains 'repoProfiles') -or -not $Config.agentctl.repoProfiles) {
        $Config.agentctl | Add-Member -NotePropertyName 'repoProfiles' -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    return $Config
}

function Test-WtwAgentCtlProfileExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Profile
    )

    $profilePath = Join-Path $HOME ".config/agent-profile/$Profile.md"
    return Test-Path $profilePath
}

function Get-WtwAgentCtlConfigForEdit {
    [CmdletBinding()]
    param()

    $config = Get-WtwConfig
    if (-not $config) {
        $config = New-WtwDefaultConfig
    }

    return Ensure-WtwAgentCtlConfig -Config $config
}

function Resolve-WtwAgentCtlRepoName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoName
    )

    $registry = Get-WtwRegistry
    if (-not $registry -or -not $registry.repos) {
        return $RepoName
    }

    foreach ($name in $registry.repos.PSObject.Properties.Name) {
        if ($name -eq $RepoName) {
            return $name
        }
        $repo = $registry.repos.$name
        if (Test-WtwAliasMatch $repo $RepoName) {
            return $name
        }
    }

    return $RepoName
}

function Set-WtwAgentCtlRepoProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoName,

        [Parameter(Mandatory)]
        [string] $Profile
    )

    $resolvedRepoName = Resolve-WtwAgentCtlRepoName -RepoName $RepoName
    $config = Get-WtwAgentCtlConfigForEdit
    if ($resolvedRepoName -ne $RepoName -and ($config.agentctl.repoProfiles.PSObject.Properties.Name -contains $RepoName)) {
        $config.agentctl.repoProfiles.PSObject.Properties.Remove($RepoName)
    }
    $config.agentctl.repoProfiles | Add-Member -NotePropertyName $resolvedRepoName -NotePropertyValue $Profile -Force
    Save-WtwConfig $config

    if ($resolvedRepoName -eq $RepoName) {
        Write-Host "  agentctl profile for '$resolvedRepoName': $Profile" -ForegroundColor Green
    } else {
        Write-Host "  agentctl profile for '$resolvedRepoName' ($RepoName): $Profile" -ForegroundColor Green
    }
    if (-not (Test-WtwAgentCtlProfileExists -Profile $Profile)) {
        Write-Warning "Profile '$Profile' was saved, but ~/.config/agent-profile/$Profile.md does not exist yet."
    }
}

function Set-WtwAgentCtlDefaultProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Profile
    )

    $config = Get-WtwAgentCtlConfigForEdit
    $config.agentctl.defaultProfile = $Profile
    Save-WtwConfig $config

    Write-Host "  default agentctl profile: $Profile" -ForegroundColor Green
    if (-not (Test-WtwAgentCtlProfileExists -Profile $Profile)) {
        Write-Warning "Profile '$Profile' was saved, but ~/.config/agent-profile/$Profile.md does not exist yet."
    }
}

function Get-WtwAgentCtlProfileSetting {
    [CmdletBinding()]
    param(
        [string] $RepoName
    )

    $config = Get-WtwAgentCtlConfigForEdit

    if ($RepoName) {
        $resolvedRepoName = Resolve-WtwAgentCtlRepoName -RepoName $RepoName
        $profile = Get-WtwAgentCtlProfile -RepoName $resolvedRepoName -RepoEntry ([PSCustomObject]@{}) -Config $config
        if ($resolvedRepoName -eq $RepoName) {
            Write-Host "${resolvedRepoName}: $profile"
        } else {
            Write-Host "${resolvedRepoName} ($RepoName): $profile"
        }
        return
    }

    Write-Host "agentctl enabled: $($config.agentctl.enabled)"
    Write-Host "default profile:  $($config.agentctl.defaultProfile)"
    Write-Host 'repo profiles:'
    $names = @($config.agentctl.repoProfiles.PSObject.Properties.Name | Sort-Object)
    if ($names.Count -eq 0) {
        Write-Host '  (none)'
        return
    }
    foreach ($name in $names) {
        Write-Host "  ${name}: $($config.agentctl.repoProfiles.$name)"
    }
}
