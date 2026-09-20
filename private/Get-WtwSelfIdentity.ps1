function Get-WtwDefaultSelfEmoji {
    <#
    .SYNOPSIS
        Platform emoji used when ~/.wtw/config.json has no ``self.emoji``.
    #>
    [CmdletBinding()]
    param()

    if ($IsWindows) { return '🪟' }
    if ($IsMacOS) { return '🍏' }
    return '🐧'
}

function Get-WtwDefaultSelfLabel {
    <#
    .SYNOPSIS
        Two-letter label from this machine's hostname when ``self.label`` is unset.
    #>
    [CmdletBinding()]
    param()

    $name = $null
    try { $name = [System.Net.Dns]::GetHostName() } catch { $name = $null }
    if (-not $name -and $env:COMPUTERNAME) { $name = $env:COMPUTERNAME }
    if (-not $name) { return 'LO' }

    $label = (($name -split '\.')[0]).Trim()
    if (-not $label) { return 'LO' }
    if ($label.Length -ge 2) { return $label.Substring(0, 2).ToUpperInvariant() }
    return $label.ToUpperInvariant()
}

function Get-WtwSelfIdentity {
    <#
    .SYNOPSIS
        Local machine badge for cmux groups (``🍏SP``).
    .DESCRIPTION
        Stored under ``self`` in ~/.wtw/config.json. Missing fields fall back to
        a platform emoji and the first two letters of the hostname.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Config
    )

    if (-not $Config) { $Config = Get-WtwConfig }
    $self = Get-WtwPropertyValue -Object $Config -Name 'self'
    $emoji = ConvertTo-WtwNormalizedRepoEmoji (Get-WtwPropertyValue -Object $self -Name 'emoji')
    if (-not $emoji) { $emoji = Get-WtwDefaultSelfEmoji }

    $label = ("$(Get-WtwPropertyValue -Object $self -Name 'label')" -replace '\s+', '').Trim()
    if (-not $label) { $label = Get-WtwDefaultSelfLabel }

    return [PSCustomObject]@{
        Emoji = $emoji
        Label = $label
        Badge = "$emoji$label"
    }
}

function Get-WtwSelfBadge {
    <#
    .SYNOPSIS
        Compact local machine prefix (emoji + label, no separator).
    #>
    [CmdletBinding()]
    param()

    return (Get-WtwSelfIdentity).Badge
}

function Get-WtwMachineBadge {
    <#
    .SYNOPSIS
        Machine half of a cmux group name: ``🍏SP`` or ``🧊AT``.
    .DESCRIPTION
        Host title prefixes include a trailing separator (``🧊AT.`` / ``🧊AT ``)
        for worktree titles. Group names put ``/`` between machine and repo, so
        the separator is stripped.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $HostEntry
    )

    if (-not $HostEntry) { return Get-WtwSelfBadge }

    $prefix = Get-WtwHostTitlePrefix -HostEntry $HostEntry
    $separator = [string](Get-WtwPropertyValue -Object $HostEntry -Name 'Separator' -DefaultValue '.')
    if ($separator.Length -gt 0 -and $prefix.EndsWith($separator)) {
        return $prefix.Substring(0, $prefix.Length - $separator.Length)
    }
    return $prefix
}

function Set-WtwSelfIdentity {
    <#
    .SYNOPSIS
        Write ``self.emoji`` / ``self.label`` in ~/.wtw/config.json.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [object] $Emoji,

        [AllowNull()]
        [AllowEmptyString()]
        [string] $Label
    )

    $config = Get-WtwConfig
    if (-not $config) { $config = New-WtwDefaultConfig }

    $self = Get-WtwPropertyValue -Object $config -Name 'self'
    if (-not $self) { $self = [PSCustomObject]@{} }

    if ($PSBoundParameters.ContainsKey('Emoji')) {
        $normalized = ConvertTo-WtwNormalizedRepoEmoji $Emoji
        if ($normalized) {
            $self | Add-Member -NotePropertyName 'emoji' -NotePropertyValue $normalized -Force
        } elseif ((Get-WtwPropertyNames -Object $self) -contains 'emoji') {
            $self.PSObject.Properties.Remove('emoji')
        }
    }

    if ($PSBoundParameters.ContainsKey('Label')) {
        $trimmed = ("$Label" -replace '\s+', '').Trim()
        if ($trimmed) {
            $self | Add-Member -NotePropertyName 'label' -NotePropertyValue $trimmed -Force
        } elseif ((Get-WtwPropertyNames -Object $self) -contains 'label') {
            $self.PSObject.Properties.Remove('label')
        }
    }

    $config | Add-Member -NotePropertyName 'self' -NotePropertyValue $self -Force
    Save-WtwConfig $config
    return Get-WtwSelfIdentity -Config $config
}

function Show-WtwSelfIdentity {
    <#
    .SYNOPSIS
        Print the local machine badge used in cmux groups.
    #>
    [CmdletBinding()]
    param()

    $self = Get-WtwSelfIdentity
    Write-WtwHost ''
    Write-WtwHost "  this machine  $($self.Badge)" -ForegroundColor Green
    Write-WtwHost "  cmux groups   $($self.Badge)/<repo>" -ForegroundColor DarkGray
    Write-WtwHost '  change with   wtw host self --emoji 🍏 --label SP' -ForegroundColor DarkGray
    Write-WtwHost ''
}
