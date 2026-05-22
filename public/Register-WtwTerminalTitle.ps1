function Register-WtwTerminalTitle {
    <#
    .SYNOPSIS
        Wire up terminal title (and tab color) for a repository session.
    .DESCRIPTION
        Performs a one-shot PR lookup, builds the initial window title via
        Get-WtwWindowTitle, applies it with Set-WtwTerminalColor, then installs
        a per-prompt hook so the branch name stays current as you work.

        The hook re-applies the tab color on iTerm2 to survive dark/light mode
        switches. It appends an OSC 0 escape after the underlying prompt output
        (Starship, Oh-My-Posh, etc.) so the wtw title always wins the last-write
        race on terminals that honor OSC 0.

        Safe to call from any repository's start-repository-session.ps1.
        Repeated calls update the active repository/title state while keeping a
        single prompt hook installed.
    .PARAMETER RepoRoot
        Absolute path to the repository root. Defaults to the current directory.
    .PARAMETER TabColor
        Six-digit hex color for the terminal tab (#rrggbb or rrggbb).
        Passed to Set-WtwTerminalColor; silently ignored on Windows Terminal, which
        does not support runtime tab recoloring from inside the tab.
    .PARAMETER Label
        Optional free-text prefix for the title. Falls back to $env:STS_LABEL.
    .OUTPUTS
        [string] The PR number found for this branch, or $null.
    .EXAMPLE
        $pr = Register-WtwTerminalTitle -RepoRoot $PSScriptRoot -TabColor (Get-GitWorkspaceColor -path $PSScriptRoot)
        if ($pr) { Write-Host "  PR: #$pr" -ForegroundColor DarkCyan }
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $RepoRoot = $PWD.Path,
        [string] $TabColor,
        [string] $Label
    )

    $isAdmin = $false
    if ($IsWindows) {
        $isAdmin = (New-Object Security.Principal.WindowsPrincipal (
            [Security.Principal.WindowsIdentity]::GetCurrent()
        )).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    } elseif ($IsLinux -or $IsMacOS) {
        $isAdmin = ((& id -u) -eq '0')
    }

    $folderName     = Split-Path $RepoRoot -Leaf
    $effectiveLabel = if ($Label) { $Label } elseif ($env:STS_LABEL) { $env:STS_LABEL } else { $null }

    $global:_WtwSessionPrNumber = Get-WtwCurrentPrNumber
    $global:_WtwTerminalTitleState = [pscustomobject] @{
        RepoRoot   = $RepoRoot
        FolderName = $folderName
        PrNumber   = $global:_WtwSessionPrNumber
        IsAdmin    = $isAdmin
        Label      = $effectiveLabel
    }

    $title = Get-WtwWindowTitle `
        -RepoRoot   $global:_WtwTerminalTitleState.RepoRoot `
        -FolderName $global:_WtwTerminalTitleState.FolderName `
        -PrNumber   $global:_WtwTerminalTitleState.PrNumber `
        -IsAdmin:   $global:_WtwTerminalTitleState.IsAdmin `
        -Label      $global:_WtwTerminalTitleState.Label

    Set-WtwTerminalColor -Color $TabColor -Title $title
    try { $Host.UI.RawUI.WindowTitle = $title } catch {}

    $hookVersion = 2
    if ($global:_WtwTerminalTitleHookActive -and $global:_WtwTerminalTitleHookVersion -eq $hookVersion) {
        return $global:_WtwSessionPrNumber
    }
    $global:_WtwTerminalTitleHookActive = $true
    $global:_WtwTerminalTitleHookVersion = $hookVersion

    $prior      = Get-Item function:prompt -ErrorAction SilentlyContinue
    $priorBlock = if ($prior) { $prior.ScriptBlock } else { { '> ' } }

    Set-Item -Path function:global:prompt -Value {
        # ERROR PROPAGATION: capture before any other call clobbers these
        $realSuccess  = $?
        $realExitCode = $global:LASTEXITCODE

        $state = $global:_WtwTerminalTitleState
        $currentTitle = if ($state) {
            Get-WtwWindowTitle `
                -RepoRoot   $state.RepoRoot `
                -FolderName $state.FolderName `
                -PrNumber   $state.PrNumber `
                -IsAdmin:   $state.IsAdmin `
                -Label      $state.Label
        } else {
            $Host.UI.RawUI.WindowTitle
        }

        # Re-apply tab color on iTerm2 (survives dark/light mode switches)
        if ($env:WTW_TAB_COLOR -and $env:TERM_PROGRAM -eq 'iTerm.app') {
            $esc = [char]27; $bel = [char]7
            $hex = $env:WTW_TAB_COLOR -replace '^#', ''
            $r   = [convert]::ToInt32($hex.Substring(0, 2), 16)
            $g   = [convert]::ToInt32($hex.Substring(2, 2), 16)
            $b   = [convert]::ToInt32($hex.Substring(4, 2), 16)
            Write-Host "${esc}]6;1;bg;red;brightness;${r}${bel}"   -NoNewline
            Write-Host "${esc}]6;1;bg;green;brightness;${g}${bel}" -NoNewline
            Write-Host "${esc}]6;1;bg;blue;brightness;${b}${bel}"  -NoNewline
        }

        # Restore error state before delegating to the underlying prompt
        $global:LASTEXITCODE = $realExitCode
        $LASTEXITCODE        = $realExitCode
        if (-not $realSuccess) { try { throw } catch {} } else { Write-Output 'Nothing' >$null }

        $promptOutput = & $priorBlock | Out-String -NoNewline

        try { $Host.UI.RawUI.WindowTitle = $currentTitle } catch {}

        # Append OSC 0 so our title wins the last-write race over starship/OMP
        $esc = [char]27; $bel = [char]7
        "${promptOutput}${esc}]0;${currentTitle}${bel}"

        Remove-Variable realSuccess, realExitCode -ErrorAction SilentlyContinue
    }.GetNewClosure()

    return $global:_WtwSessionPrNumber
}
