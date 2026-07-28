function Open-WtwWorkspace {
    <#
    .SYNOPSIS
        Open a workspace file in the configured editor.
    .DESCRIPTION
        Opens the VS Code workspace file for the given target. Falls back to
        opening the directory if no workspace file exists. Auto-detects the
        target from cwd when no name is provided.
    .PARAMETER Name
        Target repo alias or task name (default: detected from cwd).
    .PARAMETER Repo
        Specify the parent repo when the name alone is ambiguous.
    .PARAMETER Editor
        Override the editor command (defaults to config or "code").
    .EXAMPLE
        wtw open auth
        Open the workspace for the "auth" worktree in the default editor.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Name,

        [string] $Repo,
        [object] $Editor,  # string for CLI editors; hashtable @{type='macapp'; appName=...} for open-app style
        [string] $Prompt,  # claudecode only: pre-fills the new chat's composer
        [switch] $SkipRestart
    )

    # If no name given, detect from cwd
    if (-not $Name) {
        $Name = Resolve-WtwCurrentTarget
        if (-not $Name) {
            Write-Error "Not inside a registered repo. Specify a target or cd into a repo."
            return
        }
        Write-Host "  Detected: $Name" -ForegroundColor DarkGray
    }

    $config = Get-WtwConfig
    $editorCmd = if ($Editor) { $Editor } elseif ($config.editor) { $config.editor } else { 'code' }

    $target = Resolve-WtwTarget $Name
    if (-not $target) { return }

    $editorType = if ($editorCmd -is [System.Collections.IDictionary]) {
        $editorCmd['type']
    } elseif ((Get-WtwPropertyNames -Object $editorCmd) -contains 'type') {
        $editorCmd.type
    } else {
        $null
    }

    # Superset — look up matching workspace by branch/task and open the Superset app
    if ($editorType -eq 'superset') {
        Open-WtwSupersetWorkspace -Target $target
        return
    }

    # cmux terminal workspace — select existing live workspace when possible,
    # otherwise create a new cmux workspace rooted at the target directory.
    if ($editorType -eq 'cmux') {
        Open-WtwCmuxWorkspace -Target $target
        return
    }

    # wmux terminal workspace — Windows counterpart to cmux. The current wmux
    # CLI supports creating a named workspace at a cwd.
    if ($editorType -eq 'wmux') {
        Open-WtwWmuxWorkspace -Target $target
        return
    }

    # Claude Code — the Claude desktop app hosts it, so open a new chat rooted at
    # the target directory via the app's `claude://code/new` deep link.
    if ($editorType -eq 'claudecode') {
        Open-WtwClaudeCodeWorkspace -Target $target -Editor $editorCmd -Prompt $Prompt
        return
    }

    # ChatGPT Desktop (formerly Codex) — prefer the supported CLI app launcher (`codex app <dir>`),
    # falling back to macOS open-app behavior when only the app bundle exists.
    if ($editorType -eq 'codex') {
        $dir = if ($target.WorktreeEntry) { $target.WorktreeEntry.path } else { $target.RepoEntry.mainPath }
        if (-not ($dir -and (Test-Path $dir))) {
            Write-Error "No directory found for '$Name'."
            return
        }
        $prettyName = if ($target.WorktreeEntry -and (Get-WtwPropertyNames -Object $target.WorktreeEntry) -contains 'prettyName' -and $target.WorktreeEntry.prettyName) {
            $target.WorktreeEntry.prettyName
        } elseif ($target.TaskName) {
            $target.TaskName
        } else {
            Split-Path $dir -Leaf
        }
        $fullDir = [System.IO.Path]::GetFullPath($dir)
        $codexHome = Get-WtwCodexHome
        if (Test-WtwCodexPresent -CodexHome $codexHome) {
            $globalStatePath = Join-Path $codexHome '.codex-global-state.json'
            $labelAlreadySet = Test-WtwCodexProjectLabel -ProjectPath $fullDir -PrettyName $prettyName -GlobalStatePath $globalStatePath
            Ensure-WtwCodexProjectConfig -ProjectPath $fullDir | Out-Null
            Set-WtwCodexProjectTrust -ProjectPath $fullDir -ConfigPath (Join-Path $codexHome 'config.toml')
            if ($labelAlreadySet) {
                Write-Host "  ChatGPT: sidebar label already '$prettyName'" -ForegroundColor DarkGray
            } elseif ($SkipRestart -and (Test-WtwCodexAppRunning)) {
                Write-Host "  ChatGPT: sidebar label needs restart; skipped because --skip-restart was set." -ForegroundColor DarkGray
            } else {
                $decision = Resolve-WtwCodexStateConflict -OperationLabel "set sidebar label '$prettyName'"
                if ($decision.proceed -and (Set-WtwCodexProjectLabel -ProjectPath $fullDir -PrettyName $prettyName -GlobalStatePath $globalStatePath)) {
                    Write-Host "  ChatGPT: sidebar label '$prettyName'" -ForegroundColor Green
                }
            }
        }

        if (Start-WtwCodexApp -ProjectPath $fullDir) {
            Write-Host "  Opening in ChatGPT: $fullDir" -ForegroundColor Green
            return
        }

        Write-Error "ChatGPT is not installed or not on PATH. Install ChatGPT.app or the 'codex' CLI first."
        return
    }

    # macOS/cross-platform open-app style (Claude, T3 Code, etc.) — always opens directory
    if ($editorType -eq 'macapp') {
        $appName = $editorCmd.appName
        $dir = if ($target.WorktreeEntry) { $target.WorktreeEntry.path } else { $target.RepoEntry.mainPath }
        if (-not ($dir -and (Test-Path $dir))) {
            Write-Error "No directory found for '$Name'."
            return
        }

        if ($IsMacOS) {
            $candidates = Get-WtwPropertyValue -Object $editorCmd -Name 'appNameCandidates' -DefaultValue @($appName)
            $found = $candidates | Where-Object { Test-Path "/Applications/$_.app" } | Select-Object -First 1
            if (-not $found) {
                $tried = ($candidates | ForEach-Object { "$_.app" }) -join ', '
                Write-Error "$appName is not installed. Tried: $tried"
                return
            }
            Write-Host "  Opening in ${found}: $dir" -ForegroundColor Green
            if (Get-WtwPropertyValue -Object $editorCmd -Name 'macArgsViaCli' -DefaultValue $false) {
                # `open -a` routes paths as Apple "open file" events; many Avalonia apps don't handle them,
                # and `open -n --args` silently drops --args when LSMultipleInstancesProhibited is set.
                # Invoke the inner Mach-O directly so argv reaches main() — for IPC-aware apps (e.g.
                # SourceGit), the spawned second instance forwards the path to the running first instance
                # via its named-pipe IPC and exits.
                $bin = "/Applications/$found.app/Contents/MacOS/$found"
                if (Test-Path $bin) {
                    Start-Process -FilePath $bin -ArgumentList $dir
                } else {
                    Write-Warning "Binary not found at $bin — falling back to 'open -a'."
                    & open -a $found $dir
                }
            } else {
                & open -a $found $dir
            }
        } elseif ($IsWindows -and $editorCmd.winCmd) {
            $exe = (Get-Command $editorCmd.winCmd -ErrorAction SilentlyContinue)?.Source
            if (-not $exe) {
                $probe = @(
                    (Join-Path ${env:LOCALAPPDATA} "$($editorCmd.winCmd)/$($editorCmd.winCmd).exe"),
                    (Join-Path ${env:ProgramFiles}   "$($editorCmd.winCmd)/$($editorCmd.winCmd).exe")
                ) | Where-Object { $_ -and (Test-Path $_) }
                $exe = $probe | Select-Object -First 1
            }
            if (-not $exe) { Write-Error "$appName not found on PATH or in standard locations."; return }
            Write-Host "  Opening in ${appName}: $dir" -ForegroundColor Green
            Start-Process -FilePath $exe -ArgumentList $dir
        } elseif ($IsLinux -and $editorCmd.linuxCmd) {
            $exe = (Get-Command $editorCmd.linuxCmd -ErrorAction SilentlyContinue)?.Source
            if (-not $exe) { Write-Error "'$appName' not installed (no '$($editorCmd.linuxCmd)' on PATH)."; return }
            Write-Host "  Opening in ${appName}: $dir" -ForegroundColor Green
            Start-Process -FilePath $exe -ArgumentList $dir
        } else {
            $platform = if ($IsWindows) { 'Windows' } elseif ($IsLinux) { 'Linux' } else { 'this platform' }
            Write-Warning "'$appName' app launch is not supported on $platform."
        }
        return
    }

    if ($target.WorktreeEntry) {
        $wsFile = $target.WorktreeEntry.workspace
    } else {
        $wsFile = $target.RepoEntry.templateWorkspace
    }

    # Workspace file found — open it
    if ($wsFile -and (Test-Path $wsFile)) {
        if ($editorCmd -eq 'cursor') {
            $dir = if ($target.WorktreeEntry) { $target.WorktreeEntry.path } else { $target.RepoEntry.mainPath }
            $prettyName = if ($target.WorktreeEntry -and (Get-WtwPropertyNames -Object $target.WorktreeEntry) -contains 'prettyName' -and $target.WorktreeEntry.prettyName) {
                $target.WorktreeEntry.prettyName
            } elseif ($target.TaskName) {
                $target.TaskName
            } else {
                Split-Path $dir -Leaf
            }
            $color = if ($target.WorktreeEntry -and (Get-WtwPropertyNames -Object $target.WorktreeEntry) -contains 'color') { $target.WorktreeEntry.color } else { $null }
            if ($target.WorktreeEntry) {
                $prettyWorkspacePath = Get-WtwCursorPrettyWorkspacePath -WorkspacePath $wsFile -PrettyName $prettyName -RepoName $target.RepoName
                $needsAgentsLabelMigration = [System.IO.Path]::GetFullPath($prettyWorkspacePath) -ne [System.IO.Path]::GetFullPath($wsFile)
                $canMigrate = -not $needsAgentsLabelMigration
                if ($needsAgentsLabelMigration) {
                    if ($SkipRestart -and (Test-WtwCursorAppRunning)) {
                        Write-Host '  Cursor: Agents label migration skipped because --skip-restart was set.' -ForegroundColor DarkGray
                    } else {
                        $canMigrate = Resolve-WtwCursorStateConflict -PrettyName $prettyName
                    }
                }
                if ($needsAgentsLabelMigration -and $canMigrate) {
                    $migratedWorkspace = Move-WtwCursorWorkspaceForAgents `
                        -WorkspacePath $wsFile `
                        -PrettyName $prettyName `
                        -RepoName $target.RepoName
                    if ($migratedWorkspace -ne $wsFile) {
                        $wsFile = $migratedWorkspace
                        $target.WorktreeEntry | Add-Member -NotePropertyName 'workspace' -NotePropertyValue $wsFile -Force
                        $registry = Get-WtwRegistry
                        $registry.repos.$($target.RepoName).worktrees.$($target.TaskName) = $target.WorktreeEntry
                        Save-WtwRegistry $registry
                    }
                }
            }
            Register-WtwCursorProject -WorkspacePath $wsFile -ProjectPath $dir -PrettyName $prettyName -Color $color | Out-Null
        }
        Write-Host "  Opening in ${editorCmd}: $wsFile" -ForegroundColor Green
        Invoke-WtwEditorCli -Cmd $editorCmd -Path $wsFile
        return
    }

    # No workspace file — fall back to opening the directory
    $dir = if ($target.WorktreeEntry) { $target.WorktreeEntry.path } else { $target.RepoEntry.mainPath }
    if ($dir -and (Test-Path $dir)) {
        Write-Host "  Opening in ${editorCmd}: $dir" -ForegroundColor Green
        Invoke-WtwEditorCli -Cmd $editorCmd -Path $dir
    } else {
        Write-Error "No workspace or directory found for '$Name'."
    }
}
