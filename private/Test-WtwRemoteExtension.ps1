function Test-WtwRemoteExtension {
    <#
    .SYNOPSIS
        Ensure an editor has a Remote-SSH extension, offering to install one.
    .DESCRIPTION
        Every fork ships its own: VS Code has ms-vscode-remote.remote-ssh,
        Cursor has anysphere.remote-ssh, VSCodium cannot use Microsoft's at all
        (proprietary, absent from Open VSX) and needs jeanp413.open-remote-ssh.

        Detection probes the *installed* list first and only falls back to the
        table when nothing matches, so a fork that renames its extension keeps
        working without a wtw release.
    .PARAMETER Cmd
        Logical editor name ('cursor').
    .PARAMETER Install
        Install the first known candidate when none is present, without asking.
    .PARAMETER Quiet
        Suppress the "already installed" line.
    .OUTPUTS
        The extension id in use, or $null when none is installed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Cmd,
        [switch] $Install,
        [switch] $Quiet
    )

    $member = Get-WtwEditorFamilyMember -Id $Cmd
    if (-not $member) { return $null }

    $cli = Get-WtwEditorCliName -Cmd $Cmd
    if (-not $cli) { return $null }

    $installed = @(& $cli --list-extensions 2>$null)

    # Any remote-ssh-ish extension counts, whatever it is called.
    $present = $installed | Where-Object { $_ -match 'remote-ssh|remote-openssh' } | Select-Object -First 1
    if ($present) {
        if (-not $Quiet) { Write-Host "  $($member.Name): $present" -ForegroundColor DarkGray }
        return $present
    }

    $candidate = @($member.RemoteExts) | Select-Object -First 1
    if (-not $candidate) { return $null }

    if (-not $Install) {
        Write-Host "  $($member.Name) has no Remote-SSH extension installed." -ForegroundColor Yellow
        $answer = Read-Host "  Install $candidate? [y/N]"
        if ($answer -notin @('y', 'Y', 'yes')) {
            Write-Host "  Skipped. A remote open will fail until it is installed." -ForegroundColor DarkGray
            return $null
        }
    }

    Write-Host "  Installing $candidate in $($member.Name)..." -ForegroundColor Cyan -NoNewline
    & $cli --install-extension $candidate 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host ' done' -ForegroundColor Green
        return $candidate
    }
    Write-Host ' failed' -ForegroundColor Red
    return $null
}

function Set-WtwRemotePlatform {
    <#
    .SYNOPSIS
        Pin `remote.SSH.remotePlatform` for a host in the editor's settings.
    .DESCRIPTION
        Remote-SSH to a Windows box fails with an opaque error when it guesses
        the platform wrong, and the guess is only reliable for POSIX remotes.
        This pins it — but only for Windows hosts, and only when the value is
        missing or different, because rewriting settings.json costs the user
        their comments (JSONC in, JSON out).

        A one-time `settings.json.wtw-backup` is written before the first edit
        so the comments are recoverable.
    .PARAMETER Cmd
        Logical editor name.
    .PARAMETER HostName
        SSH host name as used in the remote authority.
    .PARAMETER Platform
        Remote platform ('windows' | 'linux' | 'macos').
    .OUTPUTS
        $true when settings already matched or were updated; $false otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Cmd,
        [Parameter(Mandatory)] [string] $HostName,
        [Parameter(Mandatory)] [string] $Platform
    )

    # Only Windows remotes need the hint; leave POSIX autodetection alone.
    if ($Platform -notin @('windows', 'linux', 'macOS', 'macos')) { return $false }
    if ($Platform -ine 'windows') { return $true }

    $member = Get-WtwEditorFamilyMember -Id $Cmd
    if (-not $member) { return $false }

    $settingsPath = Get-WtwEditorSettingsPath -Member $member
    if (-not $settingsPath -or -not (Test-Path $settingsPath)) {
        Write-Host "  $($member.Name): no user settings.json found — set remote.SSH.remotePlatform manually if the connection fails." -ForegroundColor DarkGray
        return $false
    }

    $settings = Read-JsoncFile -Path $settingsPath
    if (-not $settings) { $settings = [PSCustomObject]@{} }

    $map = Get-WtwPropertyValue -Object $settings -Name 'remote.SSH.remotePlatform'
    if ($map -and (Get-WtwPropertyValue -Object $map -Name $HostName) -ieq 'windows') { return $true }

    $backup = "$settingsPath.wtw-backup"
    if (-not (Test-Path $backup)) { Copy-Item -Path $settingsPath -Destination $backup -Force }

    if (-not $map) { $map = [PSCustomObject]@{} }
    $map | Add-Member -NotePropertyName $HostName -NotePropertyValue 'windows' -Force
    $settings | Add-Member -NotePropertyName 'remote.SSH.remotePlatform' -NotePropertyValue $map -Force

    $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding utf8
    Write-Host "  $($member.Name): pinned remote.SSH.remotePlatform[$HostName] = windows" -ForegroundColor Green
    Write-Host "  (comments in settings.json were dropped; original saved as $(Split-Path $backup -Leaf))" -ForegroundColor DarkGray
    return $true
}
