function Import-WtwWorktree {
    <#
    .SYNOPSIS
        Check out a worktree that already exists on another machine.
    .DESCRIPTION
        ``wtw import --from <host> <name>`` resolves the host the same way
        ``--on`` / ``--at`` do, and the name the same way ``wtw go`` does on
        that machine. The local clone must share a git remote with it. The
        branch must not already be checked out here. The new worktree lands on
        the same branch and commit, with the same color, emoji, pretty name,
        and aliases.

        Uncommitted files stay on the other machine. A local branch that is
        ahead of, or diverged from, that commit is left alone.
    .PARAMETER From
        Host name, alias, or unique prefix. Same matching as ``wtw --on``.
    .PARAMETER Name
        Worktree search text, as you would pass to ``wtw go`` on that machine.
    .PARAMETER Via
        One-off transport: tailscale, zerotier, mdns, or lan.
    .PARAMETER Repo
        Local clone that should receive the worktree when more than one
        registered repo shares that git remote.
    .PARAMETER DryRun
        Print the repo, branch, and commit without creating a worktree.
    .PARAMETER HostEntry
        Already-resolved host. Used when ``--on`` / ``--at`` was parsed by the
        dispatcher before this command ran.
    .EXAMPLE
        wtw import --from at auth
    .EXAMPLE
        wtw import --from workstation "PF037 gamification" --dry-run
    #>
    [CmdletBinding()]
    param(
        [string] $From,
        [string] $Name,
        [string] $Via,
        [string] $Repo,
        [switch] $DryRun,
        $HostEntry
    )

    if (-not $Name) {
        Write-Error "Usage: wtw import --from <host> <name>`n  <name> is the same search as 'wtw go' on that machine."
        return
    }

    if (-not $HostEntry) {
        if ($From -is [System.Management.Automation.SwitchParameter] -or [string]::IsNullOrWhiteSpace([string]$From)) {
            Write-Error "Usage: wtw import --from <host> <name>"
            return
        }
        $From = [string]$From
        if (Test-WtwIsLocalMachine -Name $From) {
            Write-Error "'$From' is this machine. --from names the machine the worktree is already on."
            return
        }
        $HostEntry = Resolve-WtwHost -Name $From
        if (-not $HostEntry) {
            $localNames = Get-WtwLocalMachineName
            $whoAmI = if ($localNames.Count -gt 0) { " This machine is '$($localNames[0])'." } else { '' }
            Write-Error "Unknown host '$From'. Configured hosts: $((Get-WtwHostNames) -join ', ').$whoAmI Add one with: wtw host add $From --user <u> --address <ip>"
            return
        }
        if ($Via) {
            $retargeted = Resolve-WtwHostVia -HostEntry $HostEntry -Via $Via
            if (-not $retargeted) {
                $kinds = @(@($HostEntry.HostNames) | ForEach-Object { Get-WtwAddressKind -Address $_ }) | Select-Object -Unique
                Write-Error "'$($HostEntry.Name)' has no '$Via' address. It has: $($kinds -join ', ')."
                return
            }
            $HostEntry = $retargeted
            Write-WtwHost "  via $Via → $($HostEntry.Name)" -ForegroundColor DarkGray
        }
    }

    $snapshot = Get-WtwRemoteWorktreeExport -HostEntry $HostEntry -Name $Name
    if (-not $snapshot) { return }

    Import-WtwWorktreeSnapshot -Snapshot $snapshot -SourceName $HostEntry.Name -Repo $Repo -DryRun:$DryRun
}
