function Invoke-WtwCmuxRawCommand {
    [CmdletBinding()]
    param(
        [string] $CmuxBin,
        [Parameter(Mandatory)]
        [string[]] $ArgumentList
    )

    if (-not $CmuxBin) {
        return [PSCustomObject]@{ ExitCode = 127; Output = 'cmux CLI not found' }
    }

    $output = & $CmuxBin @ArgumentList 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join [Environment]::NewLine) }
}
