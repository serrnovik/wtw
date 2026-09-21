function ConvertTo-WtwCmuxGroupSlug {
    <#
    .SYNOPSIS
        Stable token for a cmux group idempotency key.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string] $Value)

    $slug = ("$Value").Trim().ToLowerInvariant()
    $slug = $slug -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if (-not $slug) { return 'unknown' }
    return $slug
}

function ConvertTo-WtwCmuxGroupKey {
    <#
    .SYNOPSIS
        Idempotency key ``wtw.group.<machine>.<repo>`` (repo omitted for host-home).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $MachineId,
        [AllowNull()][AllowEmptyString()][string] $RepoId
    )

    $machine = ConvertTo-WtwCmuxGroupSlug -Value $MachineId
    if ($RepoId) {
        return "wtw.group.$machine.$(ConvertTo-WtwCmuxGroupSlug -Value $RepoId)"
    }
    return "wtw.group.$machine"
}

function Format-WtwCmuxGroupName {
    <#
    .SYNOPSIS
        Sidebar title ``🍏SP/🎸 snowmain1`` or ``🧊AT`` when there is no repo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $MachineBadge,
        [AllowNull()][AllowEmptyString()][string] $ProjectName
    )

    if ($ProjectName) { return "$MachineBadge/$ProjectName" }
    return $MachineBadge
}

function Get-WtwCmuxWorkspaceGroupCwd {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string] $Preferred)

    if ($Preferred -and (Test-Path -LiteralPath $Preferred)) {
        return [System.IO.Path]::GetFullPath($Preferred)
    }
    if ($HOME -and (Test-Path $HOME)) {
        return [System.IO.Path]::GetFullPath($HOME)
    }
    return (Get-Location).Path
}

function Resolve-WtwLocalRepoForCmuxGroup {
    <#
    .SYNOPSIS
        Map a remote registry key or alias onto this machine's canonical repo.
    .DESCRIPTION
        Arctic Troll registers snowmain as ``snowmain``; this Mac uses
        ``snowmain1`` with ``snowmain`` as an alias. Sidebar groups should follow
        the local identity so AT and SP folders line up (``🧊AT/🎸 snowmain1``).
        Exact key wins; otherwise a unique alias match. Ambiguous aliases return
        ``$null`` so the remote name is left unchanged.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string] $RepoName)

    if (-not $RepoName) { return $null }

    $repos = Get-WtwPropertyValue -Object (Get-WtwRegistry) -Name 'repos'
    if (-not $repos) { return $null }

    $exact = Get-WtwPropertyValue -Object $repos -Name $RepoName
    if ($exact) {
        return [PSCustomObject]@{
            Name  = $RepoName
            Entry = $exact
        }
    }

    $hits = [System.Collections.Generic.List[object]]::new()
    foreach ($name in (Get-WtwPropertyNames -Object $repos)) {
        $entry = Get-WtwPropertyValue -Object $repos -Name $name
        if (Test-WtwAliasMatch -Repo $entry -Name $RepoName) {
            [void]$hits.Add([PSCustomObject]@{
                    Name  = $name
                    Entry = $entry
                })
        }
    }

    if ($hits.Count -eq 1) { return $hits[0] }
    return $null
}

function Get-WtwCmuxWorkspaceGroupKeyCandidates {
    <#
    .SYNOPSIS
        Idempotency keys that refer to the same machine/project group.
    .DESCRIPTION
        A group created from the remote key ``snowmain`` must still be found
        after we canonicalize to local ``snowmain1``.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Spec)

    $keys = [System.Collections.Generic.List[string]]::new()
    $primary = [string](Get-WtwPropertyValue -Object $Spec -Name 'Key')
    if ($primary) { [void]$keys.Add($primary) }

    $machineId = [string](Get-WtwPropertyValue -Object $Spec -Name 'MachineId')
    $repoId = [string](Get-WtwPropertyValue -Object $Spec -Name 'RepoId')
    if (-not ($machineId -and $repoId)) { return @($keys) }

    $names = [System.Collections.Generic.List[string]]::new()
    [void]$names.Add($repoId)
    $local = Resolve-WtwLocalRepoForCmuxGroup -RepoName $repoId
    if ($local) {
        [void]$names.Add([string]$local.Name)
        $rawAliases = Get-WtwPropertyValue -Object $local.Entry -Name 'aliases'
        if (-not $rawAliases) {
            $rawAliases = Get-WtwPropertyValue -Object $local.Entry -Name 'alias'
        }
        foreach ($alias in @($rawAliases)) {
            if ($alias) { [void]$names.Add([string]$alias) }
        }
    }

    foreach ($name in @($names | Select-Object -Unique)) {
        $alt = ConvertTo-WtwCmuxGroupKey -MachineId $machineId -RepoId $name
        if ($alt -and -not ($keys | Where-Object { [string]::Equals($_, $alt, [System.StringComparison]::OrdinalIgnoreCase) })) {
            [void]$keys.Add($alt)
        }
    }

    return @($keys)
}

function Get-WtwCmuxLocalWorkspaceGroupSpec {
    <#
    .SYNOPSIS
        Machine/project group for a local ``wtw cmux`` target.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Target)

    $repoName = [string](Get-WtwPropertyValue -Object $Target -Name 'RepoName')
    $repoEntry = Get-WtwPropertyValue -Object $Target -Name 'RepoEntry'
    $projectName = if ($repoName) {
        Format-WtwRepoDisplayName -Name $repoName -RepoEntry $repoEntry
    } else {
        ''
    }

    $mainPath = Get-WtwPropertyValue -Object $repoEntry -Name 'mainPath'
    $worktreePath = Get-WtwPropertyValue -Object (Get-WtwPropertyValue -Object $Target -Name 'WorktreeEntry') -Name 'path'

    return [PSCustomObject]@{
        Name      = (Format-WtwCmuxGroupName -MachineBadge (Get-WtwSelfBadge) -ProjectName $projectName)
        Key       = (ConvertTo-WtwCmuxGroupKey -MachineId 'self' -RepoId $repoName)
        Cwd       = (Get-WtwCmuxWorkspaceGroupCwd -Preferred ($mainPath ?? $worktreePath))
        MachineId = 'self'
        RepoId    = $repoName
    }
}

function Get-WtwCmuxRemoteWorkspaceGroupSpec {
    <#
    .SYNOPSIS
        Machine/project group for ``wtw --on <host> cmux [name]``.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [Parameter(Mandatory)] $Session
    )

    $remoteRepoName = [string](Get-WtwPropertyValue -Object $Session -Name 'RepoName')
    $repoEmoji = Get-WtwPropertyValue -Object $Session -Name 'RepoEmoji'
    $localMatch = Resolve-WtwLocalRepoForCmuxGroup -RepoName $remoteRepoName

    if (-not $localMatch -and -not $remoteRepoName) {
        $hint = [string](Get-WtwPropertyValue -Object $Session -Name 'Name')
        if ($hint) {
            $localTarget = $null
            try {
                $localTarget = Resolve-WtwTarget -Name $hint -SkipFuzzy -ErrorAction SilentlyContinue
            } catch {
                $localTarget = $null
            }
            if ($localTarget -and $localTarget.RepoName) {
                $localMatch = [PSCustomObject]@{
                    Name  = [string]$localTarget.RepoName
                    Entry = $localTarget.RepoEntry
                }
            }
        }
    }

    $repoName = if ($localMatch) { [string]$localMatch.Name } else { $remoteRepoName }
    if ($localMatch) {
        $localEmoji = Get-WtwRepoEmoji -RepoEntry $localMatch.Entry
        if ($localEmoji) { $repoEmoji = $localEmoji }
    }
    $projectName = if ($repoName) {
        Format-WtwRepoDisplayName -Name $repoName -Emoji $repoEmoji
    } else {
        ''
    }

    $hostName = [string](Get-WtwPropertyValue -Object $HostEntry -Name 'Name')
    return [PSCustomObject]@{
        Name      = (Format-WtwCmuxGroupName -MachineBadge (Get-WtwMachineBadge -HostEntry $HostEntry) -ProjectName $projectName)
        Key       = (ConvertTo-WtwCmuxGroupKey -MachineId $hostName -RepoId $repoName)
        Cwd       = (Get-WtwCmuxWorkspaceGroupCwd)
        MachineId = $hostName
        RepoId    = $repoName
    }
}

function ConvertFrom-WtwCmuxWorkspaceGroupObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Group)

    $members = @(Get-WtwCmuxObjectValue -Object $Group -Names @('member_workspace_refs', 'memberWorkspaceRefs'))
    $generated = Get-WtwCmuxObjectValue -Object $Group -Names @('anchor_workspace_is_generated', 'anchorWorkspaceIsGenerated')
    return [PSCustomObject]@{
        Ref         = [string](Get-WtwCmuxObjectValue -Object $Group -Names @('ref', 'group_ref', 'groupRef'))
        Name        = [string](Get-WtwCmuxObjectValue -Object $Group -Names @('name', 'title'))
        Key         = [string](Get-WtwCmuxObjectValue -Object $Group -Names @('idempotency_key', 'idempotencyKey', 'external_id', 'externalId'))
        AnchorRef   = [string](Get-WtwCmuxObjectValue -Object $Group -Names @('anchor_workspace_ref', 'anchorWorkspaceRef'))
        Generated   = [bool]$generated
        MemberRefs  = @($members | ForEach-Object { "$_" } | Where-Object { $_ })
    }
}

function Get-WtwCmuxWorkspaceGroups {
    <#
    .SYNOPSIS
        Live cmux sidebar groups in the current window.
    #>
    [CmdletBinding()]
    param()

    $result = Invoke-WtwCmuxCommand -ArgumentList @('workspace-group', 'list', '--json')
    if ($result.ExitCode -ne 0) { return @() }

    $parsed = ConvertFrom-WtwCmuxJsonOutput -Output $result.Output
    if (-not $parsed) { return @() }

    $raw = if ((Get-WtwPropertyNames -Object $parsed) -contains 'groups') {
        @($parsed.groups)
    } elseif ($parsed -is [array]) {
        @($parsed)
    } else {
        @()
    }

    return @($raw | Where-Object { $_ } | ForEach-Object { ConvertFrom-WtwCmuxWorkspaceGroupObject -Group $_ })
}

function Find-WtwCmuxWorkspaceGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Spec)

    $groups = @(Get-WtwCmuxWorkspaceGroups)
    $candidates = @(Get-WtwCmuxWorkspaceGroupKeyCandidates -Spec $Spec)
    $byKey = $groups | Where-Object {
        $groupKey = [string](Get-WtwPropertyValue -Object $_ -Name 'Key')
        if (-not $groupKey) { return $false }
        foreach ($candidate in $candidates) {
            if ([string]::Equals($candidate, $groupKey, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
        return $false
    } | Select-Object -First 1
    if ($byKey) { return $byKey }

    return $groups | Where-Object {
        $_.Name -and [string]::Equals($_.Name, $Spec.Name, [System.StringComparison]::Ordinal)
    } | Select-Object -First 1
}

function Sync-WtwCmuxWorkspaceGroupAnchorTitle {
    <#
    .SYNOPSIS
        Keep a generated group header titled as the machine/project name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Group,
        [Parameter(Mandatory)][string] $Name
    )

    $anchor = Get-WtwPropertyValue -Object $Group -Name 'AnchorRef'
    $generated = [bool](Get-WtwPropertyValue -Object $Group -Name 'Generated')
    if (-not ($anchor -and $generated -and $Name)) { return }

    Invoke-WtwCmuxCommand -ArgumentList @(
        'workspace-action', '--workspace', "$anchor",
        '--action', 'rename', '--title', $Name
    ) | Out-Null
}

function Ensure-WtwCmuxWorkspaceGroup {
    <#
    .SYNOPSIS
        Find or create the generated-header group for a machine/project pair.
    .DESCRIPTION
        Uses ``cmux workspace-group create`` without ``--from`` so the header is
        a generated workspace, not the first worktree. Recreate is keyed by
        ``wtw.group.<machine>.<repo>``. If the stored name drifted (emoji or
        label change), the group is renamed in place.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Spec)

    if (-not ($Spec.Name -and $Spec.Key)) { return $null }

    $existing = Find-WtwCmuxWorkspaceGroup -Spec $Spec
    if ($existing -and $existing.Ref) {
        if ($existing.Name -and -not [string]::Equals($existing.Name, $Spec.Name, [System.StringComparison]::Ordinal)) {
            Invoke-WtwCmuxCommand -ArgumentList @('workspace-group', 'rename', $existing.Ref, '--name', $Spec.Name) | Out-Null
            $existing.Name = $Spec.Name
        }
        Sync-WtwCmuxWorkspaceGroupAnchorTitle -Group $existing -Name $Spec.Name
        return $existing
    }

    $create = Invoke-WtwCmuxCommand -ArgumentList @(
        'workspace-group', 'create',
        '--name', $Spec.Name,
        '--cwd', $Spec.Cwd,
        '--idempotency-key', $Spec.Key,
        '--external-id', $Spec.Key,
        '--json'
    )
    $parsed = ConvertFrom-WtwCmuxJsonOutput -Output $create.Output
    $rawGroup = Get-WtwPropertyValue -Object $parsed -Name 'group'
    if ($rawGroup) {
        $created = ConvertFrom-WtwCmuxWorkspaceGroupObject -Group $rawGroup
        Sync-WtwCmuxWorkspaceGroupAnchorTitle -Group $created -Name $Spec.Name
        return $created
    }

    return Find-WtwCmuxWorkspaceGroup -Spec $Spec
}

function Get-WtwCmuxNewWorkspaceGroupArgs {
    <#
    .SYNOPSIS
        Extra ``new-workspace`` flags that place the tab into a group.
    #>
    [CmdletBinding()]
    param([AllowNull()] $Group)

    $ref = Get-WtwPropertyValue -Object $Group -Name 'Ref'
    if (-not $ref) { return @() }
    return @('--group', "$ref")
}

function Add-WtwCmuxWorkspaceToGroup {
    <#
    .SYNOPSIS
        Attach an already-open workspace to its machine/project group.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] $Group,
        [AllowNull()][AllowEmptyString()][string] $WorkspaceRef
    )

    $groupRef = Get-WtwPropertyValue -Object $Group -Name 'Ref'
    if (-not ($groupRef -and $WorkspaceRef)) { return }

    $members = @(Get-WtwPropertyValue -Object $Group -Name 'MemberRefs' -DefaultValue @())
    if ($members -contains $WorkspaceRef) { return }

    Invoke-WtwCmuxCommand -ArgumentList @(
        'workspace-group', 'add',
        '--group', "$groupRef",
        '--workspace', "$WorkspaceRef"
    ) | Out-Null
}

function Resolve-WtwCmuxWorkspaceGroup {
    <#
    .SYNOPSIS
        Ensure the group exists, then optionally attach a live workspace.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Spec,
        [AllowNull()][AllowEmptyString()][string] $WorkspaceRef
    )

    $group = Ensure-WtwCmuxWorkspaceGroup -Spec $Spec
    if ($WorkspaceRef) {
        Add-WtwCmuxWorkspaceToGroup -Group $group -WorkspaceRef $WorkspaceRef
    }
    return $group
}
