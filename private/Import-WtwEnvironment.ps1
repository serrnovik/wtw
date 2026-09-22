function ConvertTo-WtwCanonicalGitUrl {
    <#
    .SYNOPSIS
        Identity of a git remote, so two clones of one repo compare equal.
    .DESCRIPTION
        `git@host:org/repo.git`, `https://host/org/repo`, and `ssh://git@host/org/repo.git`
        collapse to `host/org/repo`. Local paths (a bare repo used as origin) collapse
        to a symlink-resolved filesystem path.
    #>
    [CmdletBinding()]
    param([AllowNull()] [string] $Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    $text = $Url.Trim().TrimEnd('/', '\')

    # scp-style: git@github.com:org/repo.git  (no scheme)
    if ($text -notmatch '://' -and $text -match '^[^@\s]+@(?<host>[^:]+):(?<path>.+)$') {
        return (Format-WtwGitHostPath -GitHost $Matches.host -GitPath $Matches.path)
    }

    if ($text -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        $asUri = $text
        if ($asUri -match '^file://(?<path>/.*)$') {
            return (ConvertTo-WtwCanonicalLocalGitPath -Path $Matches.path)
        }
        try {
            $uri = [Uri]$asUri
            if ($uri.Host) {
                return (Format-WtwGitHostPath -GitHost $uri.Host -GitPath $uri.AbsolutePath)
            }
        } catch {
            Write-Verbose "git url '$text' is not a URI: $_"
        }
    }

    return (ConvertTo-WtwCanonicalLocalGitPath -Path $text)
}

function Format-WtwGitHostPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $GitHost,
        [Parameter(Mandatory)] [string] $GitPath
    )

    $hostName = $GitHost.ToLowerInvariant()
    $path = $GitPath.Trim().Trim('/').TrimEnd('/')
    $path = $path -replace '\.git$', ''
    $path = $path.ToLowerInvariant()
    if (-not $path) { return $hostName }
    return "$hostName/$path"
}

function ConvertTo-WtwCanonicalLocalGitPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $candidate = $Path -replace '^file://', ''
    $candidate = $candidate -replace '\\', '/'
    if (Test-Path -LiteralPath $candidate) {
        $real = Resolve-WtwRealPath -Path $candidate
        if ($real) { return $real.TrimEnd('/', '\') }
    }
    return $candidate.TrimEnd('/', '\')
}

function Get-WtwGitFetchRemotes {
    <#
    .SYNOPSIS
        Fetch remotes of a checkout: name + url.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepoPath)

    $found = @()
    if (-not (Test-Path -LiteralPath $RepoPath)) { return , @() }
    foreach ($line in @(git -C $RepoPath remote -v 2>$null)) {
        $text = "$line"
        if ($text -match '^(?<name>\S+)\s+(?<url>\S+)\s+\(fetch\)$') {
            $remoteName = $Matches.name
            $remoteUrl = $Matches.url
            $found += [PSCustomObject]@{ name = $remoteName; url = $remoteUrl }
        }
    }
    return , @($found)
}

function Get-WtwWorktreeFolderSuffix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoName,
        [Parameter(Mandatory)] [string] $TaskName,
        [AllowNull()] [string] $WorktreePath
    )

    if ($WorktreePath) {
        $leaf = Split-Path -Path $WorktreePath -Leaf
        $prefix = "${RepoName}_"
        if ($leaf.StartsWith($prefix, [System.StringComparison]::Ordinal) -and $leaf.Length -gt $prefix.Length) {
            return $leaf.Substring($prefix.Length)
        }
    }
    return $TaskName
}

function New-WtwWorktreeExportFromTarget {
    <#
    .SYNOPSIS
        Snapshot another machine needs in order to recreate this worktree.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Target)

    $entry = $Target.WorktreeEntry
    $path = [string](Get-WtwPropertyValue -Object $entry -Name 'path')
    $main = [string](Get-WtwPropertyValue -Object $Target.RepoEntry -Name 'mainPath')
    if (-not $main) { $main = $path }

    $branchText = "$(@(git -C $path rev-parse --abbrev-ref HEAD 2>$null) | Select-Object -First 1)".Trim()
    $detached = (-not $branchText -or $branchText -eq 'HEAD')
    $branch = if ($detached) { $null } else { $branchText }
    $commit = "$(@(git -C $path rev-parse HEAD 2>$null) | Select-Object -First 1)".Trim()
    if (-not $commit) {
        Write-Error "Could not read HEAD of $path."
        return $null
    }

    $dirtyLines = @(git -C $path status --porcelain 2>$null | Where-Object { "$_".Trim() })
    # These helpers `return , @()`. Wrapping that single array in @() nests it,
    # and strict mode then cannot read .url / the alias strings.
    $aliases = Get-WtwWorktreeAliases -Worktree $entry
    if ($null -eq $aliases) { $aliases = @() }
    $repoAliases = @()
    $repoProps = @(Get-WtwPropertyNames -Object $Target.RepoEntry)
    if ($repoProps -contains 'aliases' -or $repoProps -contains 'alias') {
        $repoAliases = Get-WtwRepoAliases -Repo $Target.RepoEntry
        if ($null -eq $repoAliases) { $repoAliases = @() }
    }
    $remotes = Get-WtwGitFetchRemotes -RepoPath $main
    if ($null -eq $remotes) { $remotes = @() }

    return [PSCustomObject]@{
        kind         = 'wtw-export'
        version      = 1
        error        = $null
        repo         = $Target.RepoName
        repoAliases  = $repoAliases
        repoEmoji    = (Get-WtwRepoEmoji -RepoEntry $Target.RepoEntry)
        remotes      = $remotes
        task         = $Target.TaskName
        branch       = $branch
        commit       = $commit
        detached     = [bool]$detached
        folderSuffix = (Get-WtwWorktreeFolderSuffix -RepoName $Target.RepoName -TaskName $Target.TaskName -WorktreePath $path)
        color        = Get-WtwPropertyValue -Object $entry -Name 'color'
        prettyName   = Get-WtwPropertyValue -Object $entry -Name 'prettyName'
        emoji        = Get-WtwPropertyValue -Object $entry -Name 'emoji'
        aliases      = $aliases
        dirty        = ($dirtyLines.Count -gt 0)
    }
}

function Get-WtwWorktreeExport {
    <#
    .SYNOPSIS
        Resolve a local worktree the way ``wtw go`` does, and describe it for import.
    .DESCRIPTION
        ``wtw __export_json`` prints this. A name that resolves to the main checkout
        returns an export with error=main so the other machine can say so, instead
        of creating a second checkout of the default branch.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)

    $target = & { Resolve-WtwTarget -Name $Name } 6>$null
    if (-not $target) { return $null }
    if (-not $target.TaskName -or -not $target.WorktreeEntry) {
        return [PSCustomObject]@{
            kind  = 'wtw-export'
            error = 'main'
            repo  = $target.RepoName
        }
    }
    return (New-WtwWorktreeExportFromTarget -Target $target)
}

function ConvertFrom-WtwWorktreeExportText {
    <#
    .SYNOPSIS
        Parse a ``wtw-export`` JSON document out of remote stdout.
    #>
    [CmdletBinding()]
    param([AllowNull()] [string] $Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $start = $Text.IndexOf('{')
    $end = $Text.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) { return $null }
    $json = $Text.Substring($start, ($end - $start + 1))
    try {
        $obj = $json | ConvertFrom-Json
    } catch {
        return $null
    }
    if ((Get-WtwPropertyValue -Object $obj -Name 'kind') -ne 'wtw-export') { return $null }
    return $obj
}

function New-WtwRemoteExportScript {
    <#
    .SYNOPSIS
        PowerShell run on a machine whose wtw predates ``__export_json``.
    .DESCRIPTION
        Prefers Get-WtwWorktreeExport when that function exists in the remote
        module. Otherwise collects the same fields with Resolve-WtwTarget and git,
        which gallery builds already have.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)

    $literal = "'" + $Name.Replace("'", "''") + "'"
    $head = @'
$ErrorActionPreference = 'Continue'
$env:WTW_NO_UPDATE_NOTICE = '1'
if ($PSStyle) { $PSStyle.OutputRendering = 'PlainText' }
$wtwModule = Join-Path $HOME '.wtw' 'module' 'wtw.psm1'
if (Test-Path -LiteralPath $wtwModule) {
    Import-Module $wtwModule -Force -DisableNameChecking
} else {
    Import-Module wtw -DisableNameChecking
}
$module = Get-Module wtw
if (-not $module) { Write-Error 'wtw is not installed on this machine.'; exit 1 }
$json = & $module {
    param($ExportName)
    $exporter = Get-Command -Name Get-WtwWorktreeExport -ErrorAction SilentlyContinue
    if ($exporter) {
        $export = Get-WtwWorktreeExport -Name $ExportName
        if (-not $export) { return $null }
        return ($export | ConvertTo-Json -Compress -Depth 8)
    }
    $target = Resolve-WtwTarget -Name $ExportName
    if (-not $target) { return $null }
    if (-not $target.TaskName -or -not $target.WorktreeEntry) {
        return ([PSCustomObject]@{ kind = 'wtw-export'; error = 'main'; repo = $target.RepoName } | ConvertTo-Json -Compress)
    }
    $entry = $target.WorktreeEntry
    $path = [string]$entry.path
    $main = [string]$target.RepoEntry.mainPath
    if (-not $main) { $main = $path }
    $branchText = "$(@(git -C $path rev-parse --abbrev-ref HEAD 2>$null) | Select-Object -First 1)".Trim()
    $detached = (-not $branchText -or $branchText -eq 'HEAD')
    $branch = if ($detached) { $null } else { $branchText }
    $commit = "$(@(git -C $path rev-parse HEAD 2>$null) | Select-Object -First 1)".Trim()
    $dirty = @(git -C $path status --porcelain 2>$null | Where-Object { "$_".Trim() }).Count -gt 0
    $remotes = @()
    foreach ($line in @(git -C $main remote -v 2>$null)) {
        if ("$line" -match '^(?<name>\S+)\s+(?<url>\S+)\s+\(fetch\)$') {
            $remotes += [PSCustomObject]@{ name = $Matches.name; url = $Matches.url }
        }
    }
    $leaf = Split-Path -Path $path -Leaf
    $prefix = "$($target.RepoName)_"
    $suffix = [string]$target.TaskName
    if ($leaf.StartsWith($prefix) -and $leaf.Length -gt $prefix.Length) { $suffix = $leaf.Substring($prefix.Length) }
    $aliases = @()
    if ($entry.PSObject.Properties['aliases'] -and $entry.aliases) { $aliases = @($entry.aliases) }
    $emoji = if ($entry.PSObject.Properties['emoji']) { $entry.emoji } else { $null }
    $color = if ($entry.PSObject.Properties['color']) { $entry.color } else { $null }
    $pretty = if ($entry.PSObject.Properties['prettyName']) { $entry.prettyName } else { $null }
    [PSCustomObject]@{
        kind = 'wtw-export'; version = 1; error = $null
        repo = $target.RepoName; task = $target.TaskName
        branch = $branch; commit = $commit; detached = [bool]$detached
        folderSuffix = $suffix; color = $color; prettyName = $pretty
        emoji = $emoji; aliases = @($aliases); dirty = [bool]$dirty
        remotes = @($remotes)
    } | ConvertTo-Json -Compress -Depth 8
} 
'@
    $tail = @'

if (-not $json) { exit 1 }
Write-Output $json
'@
    return ($head + $literal + $tail)
}

function Get-WtwRemoteWorktreeExport {
    <#
    .SYNOPSIS
        Ask another machine for the worktree snapshot ``import`` applies locally.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $HostEntry,
        [Parameter(Mandatory)] [string] $Name
    )

    $primary = Invoke-WtwRemoteCommand -HostEntry $HostEntry -Arguments @('__export_json', $Name)
    if ($primary.Error -and (Test-WtwIsSshTransportError -ErrorText $primary.Error)) {
        Write-WtwSshFailure -HostEntry $HostEntry -ErrorText $primary.Error
        return $null
    }

    $parsed = ConvertFrom-WtwWorktreeExportText -Text (($primary.Output -join "`n"))
    if (-not $parsed) {
        # Gallery wtw without __export_json treats that token as ``wtw go``.
        $script = New-WtwRemoteExportScript -Name $Name
        $fallback = Invoke-WtwRemoteCommand -HostEntry $HostEntry -Script $script
        if ($fallback.Error -and (Test-WtwIsSshTransportError -ErrorText $fallback.Error)) {
            Write-WtwSshFailure -HostEntry $HostEntry -ErrorText $fallback.Error
            return $null
        }
        $parsed = ConvertFrom-WtwWorktreeExportText -Text (($fallback.Output -join "`n"))
        if (-not $parsed) {
            Show-WtwRemoteTargetSuggestions -HostEntry $HostEntry -Name $Name
            Write-Error "'$Name' did not resolve to a worktree on $($HostEntry.Name)."
            return $null
        }
    }

    if ((Get-WtwPropertyValue -Object $parsed -Name 'error') -eq 'main') {
        $repo = Get-WtwPropertyValue -Object $parsed -Name 'repo'
        Write-Error "'$Name' is the main checkout of '$repo' on $($HostEntry.Name). Import copies a worktree."
        return $null
    }
    return $parsed
}

function Find-WtwLocalRepoByGitRemotes {
    <#
    .SYNOPSIS
        Local registered repos that share a fetch URL with the remote snapshot.
        Always an array: empty, one, or several.
    #>
    [CmdletBinding()]
    param([AllowNull()] [object[]] $Remotes)

    $wanted = @{}
    foreach ($remote in $Remotes) {
        $url = Get-WtwPropertyValue -Object $remote -Name 'url'
        $canon = ConvertTo-WtwCanonicalGitUrl -Url $url
        if ($canon) { $wanted[$canon] = $true }
    }
    if ($wanted.Count -eq 0) { return , @() }

    $registry = Get-WtwRegistry
    # Not $matches — that name is the automatic regex variable, and -match
    # inside Get-WtwGitFetchRemotes would wipe the list we are building.
    $found = @()
    foreach ($repoName in (Get-WtwPropertyNames -Object $registry.repos)) {
        $entry = $registry.repos.$repoName
        $main = [string](Get-WtwPropertyValue -Object $entry -Name 'mainPath')
        if (-not $main -or -not (Test-Path -LiteralPath $main)) { continue }
        foreach ($localRemote in (Get-WtwGitFetchRemotes -RepoPath $main)) {
            $canon = ConvertTo-WtwCanonicalGitUrl -Url (Get-WtwPropertyValue -Object $localRemote -Name 'url')
            if ($canon -and $wanted.ContainsKey($canon)) {
                $found += [PSCustomObject]@{
                    RepoName    = $repoName
                    RepoEntry   = $entry
                    LocalRemote = [string](Get-WtwPropertyValue -Object $localRemote -Name 'name')
                }
                break
            }
        }
    }

    return , @($found)
}

function Find-WtwBranchCheckout {
    <#
    .SYNOPSIS
        Path of the worktree that already has this branch checked out, or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoPath,
        [Parameter(Mandatory)] [string] $Branch
    )

    $currentPath = $null
    foreach ($line in @(git -C $RepoPath worktree list --porcelain 2>$null)) {
        $text = "$line"
        if ($text -match '^worktree (.+)$') {
            $currentPath = $Matches[1].Trim()
            continue
        }
        if ($text -eq "branch refs/heads/$Branch") {
            return $currentPath
        }
    }
    return $null
}

function Test-WtwCommitPresent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoPath,
        [Parameter(Mandatory)] [string] $Commit
    )

    git -C $RepoPath cat-file -e "$Commit^{commit}" 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Get-WtwImportBranchPlan {
    <#
    .SYNOPSIS
        How to attach a local branch to the commit the other machine is on.
    .DESCRIPTION
        Does not create anything. ``missing-commit`` means the object is not in
        this clone yet (import will fetch). ``ahead`` and ``diverged`` are refusals:
        a local branch that is not checked out still may hold commits the other
        machine does not have.
    .OUTPUTS
        @{ Action = create|adopt|fast-forward|ahead|diverged|detach|missing-commit }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoPath,
        [AllowNull()] [string] $Branch,
        [Parameter(Mandatory)] [string] $Commit,
        [bool] $Detached
    )

    if ($Detached -or [string]::IsNullOrWhiteSpace($Branch)) {
        if (-not (Test-WtwCommitPresent -RepoPath $RepoPath -Commit $Commit)) {
            return [PSCustomObject]@{ Action = 'missing-commit'; LocalCommit = $null }
        }
        return [PSCustomObject]@{ Action = 'detach'; LocalCommit = $null }
    }

    git -C $RepoPath show-ref --verify --quiet "refs/heads/$Branch" 2>$null
    $branchExists = ($LASTEXITCODE -eq 0)
    if (-not $branchExists) {
        if (-not (Test-WtwCommitPresent -RepoPath $RepoPath -Commit $Commit)) {
            return [PSCustomObject]@{ Action = 'missing-commit'; LocalCommit = $null }
        }
        return [PSCustomObject]@{ Action = 'create'; LocalCommit = $null }
    }

    $localCommit = "$(@(git -C $RepoPath rev-parse "refs/heads/$Branch" 2>$null) | Select-Object -First 1)".Trim()
    if (-not (Test-WtwCommitPresent -RepoPath $RepoPath -Commit $Commit)) {
        return [PSCustomObject]@{ Action = 'missing-commit'; LocalCommit = $localCommit }
    }
    if ($localCommit -eq $Commit) {
        return [PSCustomObject]@{ Action = 'adopt'; LocalCommit = $localCommit }
    }

    git -C $RepoPath merge-base --is-ancestor $localCommit $Commit 2>$null
    if ($LASTEXITCODE -eq 0) {
        return [PSCustomObject]@{ Action = 'fast-forward'; LocalCommit = $localCommit }
    }
    git -C $RepoPath merge-base --is-ancestor $Commit $localCommit 2>$null
    if ($LASTEXITCODE -eq 0) {
        return [PSCustomObject]@{ Action = 'ahead'; LocalCommit = $localCommit }
    }
    return [PSCustomObject]@{ Action = 'diverged'; LocalCommit = $localCommit }
}

function Sync-WtwImportCommit {
    <#
    .SYNOPSIS
        Fetch until the other machine's commit is in this clone, or give up.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoPath,
        [Parameter(Mandatory)] [string] $RemoteName,
        [AllowNull()] [string] $Branch,
        [Parameter(Mandatory)] [string] $Commit,
        [bool] $Detached
    )

    if (Test-WtwCommitPresent -RepoPath $RepoPath -Commit $Commit) { return $true }

    Write-WtwHost "  Fetching from $RemoteName..." -ForegroundColor Cyan
    if ($Branch -and -not $Detached) {
        git -C $RepoPath fetch $RemoteName "refs/heads/${Branch}:refs/remotes/${RemoteName}/${Branch}" 2>&1 | Out-Null
    }
    if (-not (Test-WtwCommitPresent -RepoPath $RepoPath -Commit $Commit)) {
        git -C $RepoPath fetch $RemoteName $Commit 2>&1 | Out-Null
    }
    if (-not (Test-WtwCommitPresent -RepoPath $RepoPath -Commit $Commit)) {
        git -C $RepoPath fetch $RemoteName 2>&1 | Out-Null
    }
    return (Test-WtwCommitPresent -RepoPath $RepoPath -Commit $Commit)
}

function Set-WtwImportUpstream {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $WorktreePath,
        [Parameter(Mandatory)] [string] $RemoteName,
        [Parameter(Mandatory)] [string] $Branch
    )

    git -C $WorktreePath rev-parse --verify --quiet "refs/remotes/$RemoteName/$Branch" 2>$null
    if ($LASTEXITCODE -ne 0) { return }
    git -C $WorktreePath branch --set-upstream-to "$RemoteName/$Branch" 2>$null | Out-Null
}

function Get-WtwShortCommit {
    param([AllowNull()] [string] $Commit)
    if (-not $Commit) { return '' }
    if ($Commit.Length -le 12) { return $Commit }
    return $Commit.Substring(0, 12)
}

function Import-WtwWorktreeSnapshot {
    <#
    .SYNOPSIS
        Create a local worktree from a remote export snapshot.
    .DESCRIPTION
        Matches the local repo by git remote URL, refuses when the branch is
        already checked out, then checks out the same branch and commit and
        registers color, emoji, pretty name, and aliases.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Snapshot,
        [string] $SourceName = 'remote',
        [switch] $DryRun
    )

    $task = [string](Get-WtwPropertyValue -Object $Snapshot -Name 'task')
    $branch = Get-WtwPropertyValue -Object $Snapshot -Name 'branch'
    $branch = if ($null -eq $branch) { '' } else { [string]$branch }
    $commit = [string](Get-WtwPropertyValue -Object $Snapshot -Name 'commit')
    $detached = [bool](Get-WtwPropertyValue -Object $Snapshot -Name 'detached' -DefaultValue $false)
    $suffix = [string](Get-WtwPropertyValue -Object $Snapshot -Name 'folderSuffix')
    if (-not $suffix) { $suffix = $task }

    if (-not $task -or -not $commit) {
        Write-Error "The snapshot from $SourceName is missing a task name or commit."
        return
    }

    $remotes = @(Get-WtwPropertyValue -Object $Snapshot -Name 'remotes')
    # Find returns `, @()`. @() around that would nest the match list.
    $localMatches = Find-WtwLocalRepoByGitRemotes -Remotes $remotes
    if ($null -eq $localMatches) { $localMatches = @() }
    if ($localMatches.Count -gt 1) {
        $names = ($localMatches | ForEach-Object { $_.RepoName }) -join ', '
        Write-Error "More than one local repo shares that git remote: $names. Unregister the extra checkout so import can tell which one you mean."
        return
    }
    if ($localMatches.Count -eq 0) {
        $shown = (@($remotes | ForEach-Object { Get-WtwPropertyValue -Object $_ -Name 'url' }) | Select-Object -First 3) -join ', '
        Write-Error "No local repo shares a git remote with '$task' on $SourceName ($shown). Clone it and run 'wtw init' in that checkout first."
        return
    }
    $local = $localMatches[0]

    $repoName = [string](Get-WtwPropertyValue -Object $local -Name 'RepoName')
    $repoEntry = $local.RepoEntry
    $mainPath = [string](Get-WtwPropertyValue -Object $repoEntry -Name 'mainPath')
    $parent = [string](Get-WtwPropertyValue -Object $repoEntry -Name 'worktreeParent')
    if (-not $parent) { $parent = Split-Path -Path $mainPath -Parent }

    $existingTasks = Get-WtwPropertyValue -Object $repoEntry -Name 'worktrees'
    if ($existingTasks -and (Get-WtwPropertyNames -Object $existingTasks) -contains $task) {
        Write-Error "Worktree '$task' is already registered under $repoName. Use 'wtw go $task'."
        return
    }

    if (-not $detached -and $branch) {
        $existingPath = Find-WtwBranchCheckout -RepoPath $mainPath -Branch $branch
        if ($existingPath) {
            Write-Error "Branch '$branch' is already checked out at $existingPath. Import leaves an existing checkout alone."
            return
        }
    }

    $worktreePath = Join-Path $parent "${repoName}_${suffix}"
    if (Test-Path -LiteralPath $worktreePath) {
        Write-Error "Path already exists: $worktreePath"
        return
    }

    $short = Get-WtwShortCommit -Commit $commit
    $plan = Get-WtwImportBranchPlan -RepoPath $mainPath -Branch $branch -Commit $commit -Detached:$detached
    $branchLabel = if ($detached -or -not $branch) { "(detached $short)" } else { $branch }

    Write-WtwHost ''
    Write-WtwHost "  Import '$task' from $SourceName" -ForegroundColor Cyan
    Write-WtwHost "  Repo:    $repoName" -ForegroundColor Green
    Write-WtwHost "  Branch:  $branchLabel" -ForegroundColor Green
    Write-WtwHost "  Commit:  $short" -ForegroundColor Green
    Write-WtwHost "  Path:    $worktreePath" -ForegroundColor Green

    if ($plan.Action -eq 'ahead') {
        Write-Error "Local branch '$branch' in $repoName is ahead of $short on $SourceName. Import will not move it backwards."
        return
    }
    if ($plan.Action -eq 'diverged') {
        Write-Error "Local branch '$branch' in $repoName has diverged from $short on $SourceName. Import will not overwrite it."
        return
    }

    $dirty = [bool](Get-WtwPropertyValue -Object $Snapshot -Name 'dirty' -DefaultValue $false)
    if ($dirty) {
        Write-WtwHost "  The worktree on $SourceName has uncommitted changes. Those files stay there." -ForegroundColor Yellow
    }

    if ($DryRun) {
        $verb = switch ($plan.Action) {
            'missing-commit' { "Would fetch $($local.LocalRemote) and check out $branchLabel." }
            'fast-forward'   { "Would fast-forward '$branch' to $short and add the worktree." }
            'create'         { "Would create '$branch' at $short." }
            'detach'         { "Would add a detached worktree at $short." }
            default          { "Would add a worktree on existing '$branch'." }
        }
        Write-WtwHost "  Dry run: $verb" -ForegroundColor DarkCyan
        Write-WtwHost ''
        return
    }

    if ($plan.Action -eq 'missing-commit') {
        $fetched = Sync-WtwImportCommit -RepoPath $mainPath -RemoteName $local.LocalRemote -Branch $branch -Commit $commit -Detached:$detached
        if (-not $fetched) {
            $pushHint = if ($branch) { "Push '$branch' from $SourceName, then run import again." } else { "Push that commit from $SourceName, then run import again." }
            Write-Error "Commit $short is not in $repoName. $pushHint"
            return
        }
        $plan = Get-WtwImportBranchPlan -RepoPath $mainPath -Branch $branch -Commit $commit -Detached:$detached
        if ($plan.Action -in @('ahead', 'diverged', 'missing-commit')) {
            Write-Error "After fetch, '$branch' in $repoName still cannot move to $short ($($plan.Action))."
            return
        }
    }

    Write-WtwHost '  Creating worktree...' -ForegroundColor Cyan
    $gitOut = $null
    if ($plan.Action -eq 'detach') {
        $gitOut = git -C $mainPath worktree add --detach $worktreePath $commit 2>&1
    } elseif ($plan.Action -eq 'create') {
        $gitOut = git -C $mainPath worktree add -b $branch $worktreePath $commit 2>&1
    } else {
        $gitOut = git -C $mainPath worktree add $worktreePath $branch 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "git worktree add failed: $gitOut"
        return
    }

    if ($plan.Action -eq 'fast-forward') {
        $mergeOut = git -C $worktreePath merge --ff-only $commit 2>&1
        if ($LASTEXITCODE -ne 0) {
            git -C $mainPath worktree remove $worktreePath --force 2>$null | Out-Null
            Write-Error "Could not fast-forward '$branch' to ${short}: $mergeOut"
            return
        }
    }

    if (-not $detached -and $branch) {
        Set-WtwImportUpstream -WorktreePath $worktreePath -RemoteName $local.LocalRemote -Branch $branch
    }

    $pretty = Get-WtwNameWithoutColorCircle -Name ([string](Get-WtwPropertyValue -Object $Snapshot -Name 'prettyName'))
    $color = [string](Get-WtwPropertyValue -Object $Snapshot -Name 'color')
    $emoji = Get-WtwPropertyValue -Object $Snapshot -Name 'emoji'
    $aliasList = @(@(Get-WtwPropertyValue -Object $Snapshot -Name 'aliases') | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    $registeredBranch = if ($detached -or -not $branch) { '(detached)' } else { $branch }

    $metaSplat = @{
        RepoName     = $repoName
        RepoEntry    = $repoEntry
        Task         = $task
        Branch       = $registeredBranch
        WorktreePath = $worktreePath
        FolderSuffix = $suffix
    }
    if ($pretty) { $metaSplat['PrettyName'] = $pretty }
    if ($color) { $metaSplat['Color'] = $color }
    if ($emoji) { $metaSplat['Emoji'] = $emoji }
    if ($aliasList.Count -gt 0) { $metaSplat['Alias'] = $aliasList }

    $meta = Initialize-WtwWorktreeMetadata @metaSplat
    if (-not $meta.Success) {
        git -C $mainPath worktree remove $worktreePath --force 2>$null | Out-Null
        return
    }

    Write-WtwHost ''
    Write-WtwHost "  Imported '$task' under $repoName from $SourceName." -ForegroundColor Green
    Write-WtwHost "  Use 'wtw go $task' to switch." -ForegroundColor Green
    Write-WtwHost ''
}
