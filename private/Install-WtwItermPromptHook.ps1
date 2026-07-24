<#
.SYNOPSIS
    Installs a prompt wrapper that re-applies the iTerm2 tab color on every prompt.

.DESCRIPTION
    Wraps the current 'prompt' function so that if $env:WTW_TAB_COLOR is set, the
    iTerm2 OSC color sequences are emitted before each prompt. This keeps the tab
    color alive after macOS dark/light mode switches, which cause iTerm2 to reload
    its profile and wipe dynamically-set tab colors.

    Safe to call multiple times; subsequent calls are no-ops.

    If you use Starship or Oh-My-Posh, call Install-WtwItermPromptHook *after*
    their init so the wrapper runs on top of their prompt function.

.NOTES
    Only installs on iTerm2 ($env:TERM_PROGRAM -eq 'iTerm.app').
    Stores a guard in $global:_WtwItermPromptHookActive to prevent double-wrapping.
#>
function Install-WtwItermPromptHook {
    [CmdletBinding()]
    param()

    if ($env:TERM_PROGRAM -ne 'iTerm.app') { return }
    $activeHook = Get-Variable -Name '_WtwItermPromptHookActive' -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($activeHook) { return }
    $global:_WtwItermPromptHookActive = $true

    $prior = Get-Item function:prompt -ErrorAction SilentlyContinue
    $priorBlock = if ($prior) { $prior.ScriptBlock } else { { '> ' } }

    Set-Item -Path function:global:prompt -Value {
        if ($env:WTW_TAB_COLOR) {
            $esc = [char]27; $bel = [char]7
            $hex = $env:WTW_TAB_COLOR -replace '^#', ''
            $r = [convert]::ToInt32($hex.Substring(0, 2), 16)
            $g = [convert]::ToInt32($hex.Substring(2, 2), 16)
            $b = [convert]::ToInt32($hex.Substring(4, 2), 16)
            Write-Host "${esc}]6;1;bg;red;brightness;${r}${bel}" -NoNewline
            Write-Host "${esc}]6;1;bg;green;brightness;${g}${bel}" -NoNewline
            Write-Host "${esc}]6;1;bg;blue;brightness;${b}${bel}" -NoNewline
        }
        & $priorBlock
    }.GetNewClosure()
}
