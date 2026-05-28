function Get-WtwAgentCtlProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoName,

        [object] $RepoEntry,
        [object] $Config
    )

    if ($RepoEntry -and ($RepoEntry.PSObject.Properties.Name -contains 'agentctlProfile') -and -not [string]::IsNullOrWhiteSpace($RepoEntry.agentctlProfile)) {
        return [string] $RepoEntry.agentctlProfile
    }

    if ($Config -and ($Config.PSObject.Properties.Name -contains 'agentctl')) {
        $agentctlConfig = $Config.agentctl
        if ($agentctlConfig -and ($agentctlConfig.PSObject.Properties.Name -contains 'repoProfiles')) {
            $repoProfiles = $agentctlConfig.repoProfiles
            if ($repoProfiles -and ($repoProfiles.PSObject.Properties.Name -contains $RepoName) -and -not [string]::IsNullOrWhiteSpace($repoProfiles.$RepoName)) {
                return [string] $repoProfiles.$RepoName
            }
        }

        if ($agentctlConfig -and ($agentctlConfig.PSObject.Properties.Name -contains 'defaultProfile') -and -not [string]::IsNullOrWhiteSpace($agentctlConfig.defaultProfile)) {
            return [string] $agentctlConfig.defaultProfile
        }
    }

    return 'team'
}

function Invoke-WtwAgentCtlAttach {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorktreePath,

        [Parameter(Mandatory)]
        [string] $RepoName,

        [object] $RepoEntry,
        [object] $Config
    )

    $agentctlCommand = Get-Command agentctl -ErrorAction SilentlyContinue
    if (-not $agentctlCommand) {
        Write-Host '  agentctl: skipped (not found on PATH)' -ForegroundColor DarkGray
        return $false
    }

    if ($Config -and ($Config.PSObject.Properties.Name -contains 'agentctl')) {
        $agentctlConfig = $Config.agentctl
        if ($agentctlConfig -and ($agentctlConfig.PSObject.Properties.Name -contains 'enabled') -and $agentctlConfig.enabled -eq $false) {
            Write-Host '  agentctl: skipped (disabled in ~/.wtw/config.json)' -ForegroundColor DarkGray
            return $false
        }
    }

    $profile = Get-WtwAgentCtlProfile -RepoName $RepoName -RepoEntry $RepoEntry -Config $Config
    Write-Host "  agentctl: attaching profile '$profile'..." -ForegroundColor Cyan

    Push-Location -LiteralPath $WorktreePath
    try {
        $output = & $agentctlCommand.Source repo attach --profile $profile 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  agentctl: attached profile '$profile'" -ForegroundColor Green
            return $true
        }

        Write-Warning "agentctl failed (exit $LASTEXITCODE): $output"
        return $false
    } finally {
        Pop-Location
    }
}
