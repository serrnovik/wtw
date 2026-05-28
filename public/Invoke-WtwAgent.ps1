function Invoke-WtwAgent {
    <#
    .SYNOPSIS
        Manage optional AI-agent integrations for wtw.
    .DESCRIPTION
        Configures the local agentctl profile mapping stored in ~/.wtw/config.json.
        The mapping is used by wtw create when agentctl is available on PATH.
    .EXAMPLE
        wtw agent profile set snowmain1 solo
        Use the solo profile for future snowmain1 worktrees.
    .EXAMPLE
        wtw agent profile default team
        Use the team profile for repos without an explicit mapping.
    #>
    $area = if ($args.Count -gt 0) { [string] $args[0] } else { '' }
    $action = if ($args.Count -gt 1) { [string] $args[1] } else { '' }

    if ($area -ne 'profile') {
        Write-Host 'Usage:' -ForegroundColor Yellow
        Write-Host '  wtw agent profile set <repo> <profile>'
        Write-Host '  wtw agent profile get [repo]'
        Write-Host '  wtw agent profile default <profile>'
        Write-Host '  wtw agent profile list'
        return
    }

    switch ($action) {
        'set' {
            if ($args.Count -lt 4) {
                Write-Error 'Usage: wtw agent profile set <repo> <profile>'
                return
            }
            Set-WtwAgentCtlRepoProfile -RepoName ([string] $args[2]) -Profile ([string] $args[3])
        }
        'get' {
            $repoName = if ($args.Count -ge 3) { [string] $args[2] } else { '' }
            Get-WtwAgentCtlProfileSetting -RepoName $repoName
        }
        'default' {
            if ($args.Count -lt 3) {
                Write-Error 'Usage: wtw agent profile default <profile>'
                return
            }
            Set-WtwAgentCtlDefaultProfile -Profile ([string] $args[2])
        }
        'list' {
            Get-WtwAgentCtlProfileSetting
        }
        default {
            Write-Host 'Usage:' -ForegroundColor Yellow
            Write-Host '  wtw agent profile set <repo> <profile>'
            Write-Host '  wtw agent profile get [repo]'
            Write-Host '  wtw agent profile default <profile>'
            Write-Host '  wtw agent profile list'
        }
    }
}
