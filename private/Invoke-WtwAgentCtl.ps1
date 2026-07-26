function Get-WtwAgentCtlProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoName,

        [object] $RepoEntry,
        [object] $Config
    )

    if ($RepoEntry -and ((Get-WtwPropertyNames -Object $RepoEntry) -contains 'agentctlProfile') -and -not [string]::IsNullOrWhiteSpace($RepoEntry.agentctlProfile)) {
        return [string] $RepoEntry.agentctlProfile
    }

    if ($Config -and ((Get-WtwPropertyNames -Object $Config) -contains 'agentctl')) {
        $agentctlConfig = $Config.agentctl
        if ($agentctlConfig -and ((Get-WtwPropertyNames -Object $agentctlConfig) -contains 'repoProfiles')) {
            $repoProfiles = $agentctlConfig.repoProfiles
            if ($repoProfiles -and ((Get-WtwPropertyNames -Object $repoProfiles) -contains $RepoName) -and -not [string]::IsNullOrWhiteSpace($repoProfiles.$RepoName)) {
                return [string] $repoProfiles.$RepoName
            }
        }

        if ($agentctlConfig -and ((Get-WtwPropertyNames -Object $agentctlConfig) -contains 'defaultProfile') -and -not [string]::IsNullOrWhiteSpace($agentctlConfig.defaultProfile)) {
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

    if ($Config -and ((Get-WtwPropertyNames -Object $Config) -contains 'agentctl')) {
        $agentctlConfig = $Config.agentctl
        if ($agentctlConfig -and ((Get-WtwPropertyNames -Object $agentctlConfig) -contains 'enabled') -and $agentctlConfig.enabled -eq $false) {
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
