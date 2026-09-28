function Invoke-WtwConfiguredSessionScript {
    <#
    .SYNOPSIS
        Run a repo session script in the current shell when one is configured.
    .DESCRIPTION
        Uses the registry sessionScript when set. Otherwise looks for
        start-repository-session.ps1 or start-tools-session.ps1 in the directory.
        Sets $script:WtwSessionScriptRan when a script file was invoked.
        Script output is passed through; the flag is not written to the pipeline.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [AllowEmptyString()]
        [string] $SessionScript
    )

    $name = $SessionScript
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = Get-WtwSessionScript -RepoPath $Path
    }
    if ([string]::IsNullOrWhiteSpace($name)) {
        return
    }

    $scriptPath = Join-Path $Path $name
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        return
    }

    & $scriptPath
    $script:WtwSessionScriptRan = $true
}

function Invoke-WtwDirectorySwitch {
    <#
    .SYNOPSIS
        Change into a worktree directory and run its session script.
    .DESCRIPTION
        Set-GitRepo (user profile) returns without running the session script
        when the shell is already in the target directory. In that case, run
        the configured script directly so aliases from that script load.

        Sets $script:WtwSessionScriptRan. Does not emit that flag on the
        pipeline, so session-script output still reaches the caller.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [AllowEmptyString()]
        [string] $SessionScript
    )

    $script:WtwSessionScriptRan = $false

    $current = ''
    $location = Get-Location
    if ($location.ProviderPath) {
        $current = [string] $location.ProviderPath
    } elseif ($location.Path) {
        $current = [string] $location.Path
    }

    if (Test-WtwSamePath $current $Path) {
        Write-WtwHost "  Already in '$Path'"
        Invoke-WtwConfiguredSessionScript -Path $Path -SessionScript $SessionScript
        return
    }

    if (Get-Command 'Set-GitRepo' -ErrorAction SilentlyContinue) {
        $toolName = if ($SessionScript) { $SessionScript } else { 'start-repository-session.ps1' }
        Set-GitRepo -gitRoot $Path -toolName $toolName
        # Set-GitRepo runs the session script when it changes directory.
        $script:WtwSessionScriptRan = $true
        return
    }

    Set-Location -LiteralPath $Path
    if ($SessionScript) {
        Invoke-WtwConfiguredSessionScript -Path $Path -SessionScript $SessionScript
    }
    Write-WtwHost "  Switched to: $Path" -ForegroundColor Green
}
