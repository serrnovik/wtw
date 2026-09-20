function Get-WtwShellTheme {
    <#
    .SYNOPSIS
        light or dark for WTW host output.
    .DESCRIPTION
        Follows the same knobs as chezmoi ``shell-theme`` so a pane that already
        ran theme.ps1 / theme.zsh needs no extra setup:

          WTW_THEME, AGENT_SHELL_THEME, STARSHIP_THEME, TERM_BACKGROUND

        Then a cheap console hint (RawUI Black ink is what theme.ps1 sets on
        Windows light, COLORFGBG, light RawUI backgrounds). No solar math —
        that lives in agent-shell; we just consume what it already applied.
    #>
    [CmdletBinding()]
    param()

    foreach ($name in @('WTW_THEME', 'AGENT_SHELL_THEME', 'STARSHIP_THEME', 'TERM_BACKGROUND')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        if ($value -match '^(?i)light$') { return 'light' }
        if ($value -match '^(?i)dark$') { return 'dark' }
    }

    try {
        $fg = [string]$Host.UI.RawUI.ForegroundColor
        if ($fg -eq 'Black') { return 'light' }
    } catch { }

    if ($env:COLORFGBG) {
        $bg = ($env:COLORFGBG -split '[;:]')[-1]
        $bgNum = 0
        if ([int]::TryParse($bg, [ref]$bgNum)) {
            if ($bgNum -ge 7) { return 'light' }
            return 'dark'
        }
    }

    try {
        $rawBg = [string]$Host.UI.RawUI.BackgroundColor
        if ($rawBg -match '^(White|Gray|Cyan|Yellow|Green|Magenta)$') { return 'light' }
    } catch { }

    return 'dark'
}

function Get-WtwThemeRgb {
    <#
    .SYNOPSIS
        R/G/B for a ConsoleColor name under the current (or given) shell theme.
    .DESCRIPTION
        Maps the 16 console colors onto the same truecolor inks agent-shell
        uses for PSReadLine / PSStyle, so ``Write-Host -ForegroundColor Yellow``
        is not washed-out yellow-on-cream after ``shell-theme light``.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ConsoleColor] $Color,

        [string] $Theme
    )

    if ([string]::IsNullOrWhiteSpace($Theme)) { $Theme = Get-WtwShellTheme }

    # [r, g, b] — light inks match Set-AgentShellLightConsole; dark inks match Restore-AgentShellDarkConsole.
    $light = @{
        Black       = @(28, 25, 23)
        DarkBlue    = @(0, 16, 128)
        DarkGreen   = @(0, 128, 0)
        DarkCyan    = @(0, 80, 160)
        DarkRed     = @(163, 21, 21)
        DarkMagenta = @(175, 0, 219)
        DarkYellow  = @(160, 90, 0)
        Gray        = @(90, 90, 90)
        DarkGray    = @(80, 80, 80)
        Blue        = @(0, 55, 180)
        Green       = @(9, 134, 88)
        Cyan        = @(0, 80, 160)
        Red         = @(205, 49, 49)
        Magenta     = @(175, 0, 219)
        Yellow      = @(160, 90, 0)
        White       = @(28, 25, 23)
    }
    $dark = @{
        Black       = @(28, 25, 23)
        DarkBlue    = @(37, 99, 235)
        DarkGreen   = @(22, 163, 74)
        DarkCyan    = @(13, 148, 136)
        DarkRed     = @(185, 28, 28)
        DarkMagenta = @(147, 51, 234)
        DarkYellow  = @(202, 138, 4)
        Gray        = @(168, 162, 158)
        DarkGray    = @(168, 162, 158)
        Blue        = @(96, 165, 250)
        Green       = @(134, 239, 172)
        Cyan        = @(125, 211, 252)
        Red         = @(248, 113, 113)
        Magenta     = @(216, 180, 254)
        Yellow      = @(251, 191, 36)
        White       = @(231, 229, 228)
    }

    $table = if ($Theme -eq 'light') { $light } else { $dark }
    $rgb = $table[$Color.ToString()]
    return [pscustomobject]@{ R = [int]$rgb[0]; G = [int]$rgb[1]; B = [int]$rgb[2] }
}

function Get-WtwThemeAnsi {
    <#
    .SYNOPSIS
        SGR truecolor prefix for optional fg/bg console colors.
    #>
    [CmdletBinding()]
    param(
        [ConsoleColor] $ForegroundColor,
        [ConsoleColor] $BackgroundColor,
        [string] $Theme
    )

    if ([string]::IsNullOrWhiteSpace($Theme)) { $Theme = Get-WtwShellTheme }
    $parts = [System.Collections.Generic.List[string]]::new()
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) {
        $rgb = Get-WtwThemeRgb -Color $ForegroundColor -Theme $Theme
        [void]$parts.Add("`e[38;2;$($rgb.R);$($rgb.G);$($rgb.B)m")
    }
    if ($PSBoundParameters.ContainsKey('BackgroundColor')) {
        $rgb = Get-WtwThemeRgb -Color $BackgroundColor -Theme $Theme
        [void]$parts.Add("`e[48;2;$($rgb.R);$($rgb.G);$($rgb.B)m")
    }
    return ($parts -join '')
}
