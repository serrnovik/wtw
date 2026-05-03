function Invoke-WtwSbx {
    <#
    .SYNOPSIS
        Launch an AI agent sandbox (sbx) for the current or named worktree.
    .DESCRIPTION
        Reads the worktree's .code-workspace file to discover all workspace
        folders, then launches `sbx run <agent>` with the primary folder
        writable and additional folders mounted read-only.

        Requires the `sbx` CLI (brew install docker/tap/sbx).
    .PARAMETER Instruction
        Optional task instruction passed after `--` to the agent.
    .PARAMETER Name
        Worktree name or alias to target (default: current directory).
    .PARAMETER Agent
        Agent to run inside the sandbox (default: claude).
    .PARAMETER Writable
        Mount all workspace folders writable instead of read-only.
    .PARAMETER DryRun
        Print the sbx command without executing it.
    .EXAMPLE
        wtw sbx
        Launch Claude sandbox in the current worktree.
    .EXAMPLE
        wtw sbx "fix the broken tests"
        Launch with an instruction.
    .EXAMPLE
        wtw sbx --name auth "refactor auth module"
        Launch for a specific worktree with an instruction.
    .EXAMPLE
        wtw sbx --agent codex --dry-run
        Preview the sbx command for the codex agent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Instruction,

        [string] $Name,
        [string] $Agent = 'claude',
        [string] $Template = 'snowmain-base',
        [switch] $Writable,
        [switch] $DryRun
    )

    if (-not (Get-Command 'sbx' -ErrorAction SilentlyContinue)) {
        Write-Host ''
        Write-Host '  ✗  sbx not found' -ForegroundColor Red
        Write-Host '     Install: brew install docker/tap/sbx' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    # Resolve target
    $targetPath   = $null
    $workspaceFile = $null

    if ($Name) {
        $target = Resolve-WtwTarget $Name
        if (-not $target) { return }
        $targetPath   = if ($target.WorktreeEntry) { $target.WorktreeEntry.path } else { $target.RepoEntry.mainPath }
        $workspaceFile = if ($target.WorktreeEntry) { $target.WorktreeEntry.workspace } else { $target.RepoEntry.templateWorkspace }
    } else {
        $targetPath = (Get-Location).Path
        $repoName, $repoEntry = Get-WtwRepoFromCwd
        if ($repoName -and $repoEntry) {
            $cwd = [System.IO.Path]::GetFullPath($targetPath)
            if ($repoEntry.worktrees) {
                foreach ($taskName in $repoEntry.worktrees.PSObject.Properties.Name) {
                    $wt = $repoEntry.worktrees.$taskName
                    if ($wt.path -and [System.IO.Path]::GetFullPath($wt.path) -eq $cwd) {
                        $workspaceFile = $wt.workspace
                        break
                    }
                }
            }
            if (-not $workspaceFile) {
                $workspaceFile = $repoEntry.templateWorkspace
            }
        }
    }

    if (-not (Test-Path $targetPath)) {
        Write-Error "Worktree path not found: $targetPath"
        return
    }

    # Build mount list: primary is writable, extras are :ro (unless --writable)
    $mounts = [System.Collections.Generic.List[string]]::new()
    $mounts.Add($targetPath)

    $extraFolders = @()
    if ($workspaceFile -and (Test-Path $workspaceFile)) {
        $ws = Read-JsoncFile $workspaceFile
        if ($ws -and $ws.folders) {
            $wsDir = Split-Path $workspaceFile -Parent
            $primaryNorm = [System.IO.Path]::GetFullPath($targetPath)
            foreach ($folder in $ws.folders) {
                $fp = $folder.path
                if ([string]::IsNullOrWhiteSpace($fp)) { continue }
                if (-not [System.IO.Path]::IsPathRooted($fp)) {
                    $fp = [System.IO.Path]::GetFullPath((Join-Path $wsDir $fp))
                }
                if ([System.IO.Path]::GetFullPath($fp) -eq $primaryNorm) { continue }
                if (-not (Test-Path $fp)) { continue }
                $extraFolders += $fp
                $mounts.Add($(if ($Writable) { $fp } else { "${fp}:ro" }))
            }
        }
    }

    # Build sbx args
    $sbxArgs = @('run', $Agent)
    if ($Template) { $sbxArgs += @('--template', $Template) }
    $sbxArgs += $mounts.ToArray()
    if ($Instruction) {
        $sbxArgs += '--'
        $sbxArgs += $Instruction
    }

    # Display
    Write-Host ''
    if ($DryRun) {
        Write-Host '  [dry-run] sbx ' -ForegroundColor DarkCyan -NoNewline
        Write-Host ($sbxArgs -join ' ') -ForegroundColor Cyan
        Write-Host ''
        return
    }

    Write-Host "  Launching $Agent sandbox" -ForegroundColor Cyan
    Write-Host "  Primary:  $targetPath" -ForegroundColor DarkGray
    foreach ($m in $extraFolders) {
        $label = if ($Writable) { '  Mount:    ' } else { '  Mount:ro: ' }
        Write-Host "$label$m" -ForegroundColor DarkGray
    }
    if ($Instruction) {
        Write-Host "  Task:     $Instruction" -ForegroundColor DarkGray
    }
    Write-Host ''

    & sbx @sbxArgs
}
