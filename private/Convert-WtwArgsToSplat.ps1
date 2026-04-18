function Convert-WtwArgsToSplat {
    <#
    .SYNOPSIS
        Parse CLI arguments into a PowerShell splatting hashtable.
    .DESCRIPTION
        Converts --kebab-case flags to PascalCase parameter names and determines
        whether each flag is a switch or a key-value pair by peeking at the next
        argument. Returns a hashtable with Splat (named params) and Positional
        (remaining args) keys.
    .PARAMETER ArgList
        Raw argument array from the CLI invocation.
    .EXAMPLE
        Convert-WtwArgsToSplat @('myTask', '--dry-run', '--repo', 'app')
        Returns @{ Splat = @{ DryRun = [switch]::Present; Repo = 'app' }; Positional = @('myTask') }
    #>
    param([object[]] $ArgList)

    $splat = [ordered]@{}
    $positional = @()
    $i = 0

    while ($i -lt $ArgList.Count) {
        $arg = "$($ArgList[$i])"

        # Translate --kebab-case to PascalCase
        if ($arg -match '^--([a-z][a-z0-9-]*)$') {
            $parts = $Matches[1] -split '-'
            $arg = '-' + (($parts | ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1) }) -join '')
        }

        if ($arg -match '^-(\w+)$') {
            $paramName = $Matches[1]
            # Peek at next arg to decide switch vs value
            if (($i + 1) -lt $ArgList.Count -and "$($ArgList[$i + 1])" -notmatch '^-') {
                $splat[$paramName] = $ArgList[$i + 1]
                $i += 2
            } else {
                $splat[$paramName] = [switch]::Present
                $i++
            }
        } else {
            $positional += $arg
            $i++
        }
    }

    # Add positional args as numbered keys won't work — return them separately
    return @{ Splat = $splat; Positional = $positional }
}
