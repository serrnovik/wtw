function Write-WtwHost {
    <#
    .SYNOPSIS
        Write-Host that keeps -ForegroundColor readable after ``shell-theme``.
    .DESCRIPTION
        ``Write-Host -ForegroundColor Yellow`` uses the 16-color Windows palette.
        chezmoi ``shell-theme`` then sets OSC 10/11 and (on Windows light)
        RawUI ink to Black. Palette yellow/cyan/darkgray on that cream
        background is the washed-out ``wtw clean`` menu.

        This wrapper still writes to the information stream (tests that
        capture ``6>&1`` keep working) but paints with the same truecolor
        inks as agent-shell PSStyle, never ``-ForegroundColor`` ConsoleColor.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromRemainingArguments)]
        [AllowEmptyString()]
        [AllowNull()]
        [object[]] $Object,

        [ConsoleColor] $ForegroundColor,
        [ConsoleColor] $BackgroundColor,
        [switch] $NoNewline
    )

    begin {
        $wrote = $false
        $hasColor = $PSBoundParameters.ContainsKey('ForegroundColor') -or $PSBoundParameters.ContainsKey('BackgroundColor')
        $useAnsi = $hasColor -and [string]::IsNullOrWhiteSpace($env:NO_COLOR)
        $prefix = ''
        if ($useAnsi) {
            $ansiArgs = @{}
            if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $ansiArgs.ForegroundColor = $ForegroundColor }
            if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $ansiArgs.BackgroundColor = $BackgroundColor }
            $prefix = Get-WtwThemeAnsi @ansiArgs
        }
    }
    process {
        $wrote = $true
        $text = if ($null -eq $Object) { '' } else { ($Object | ForEach-Object { "$_" }) -join ' ' }
        if ($useAnsi) {
            Write-Host ($prefix + $text + "`e[0m") -NoNewline:$NoNewline
            return
        }
        Write-Host $text -NoNewline:$NoNewline
    }
    end {
        if (-not $wrote) {
            if ($useAnsi) {
                Write-Host ($prefix + "`e[0m") -NoNewline:$NoNewline
                return
            }
            Write-Host '' -NoNewline:$NoNewline
        }
    }
}
