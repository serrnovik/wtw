function Get-WtwCliCommandNames {
    <#
    .SYNOPSIS
        Every wtw token that is a subcommand, not an implicit ``go`` target.
    .DESCRIPTION
        zsh/bash/cmd wrappers treat unknown first tokens as worktree names.
        This list is the source of truth for "pass this through to pwsh".
        ``go`` is included so callers can project the full CLI; wrappers still
        special-case it for a native cd.
    #>
    [CmdletBinding()]
    param()

    $core = @(
        'init', 'add', 'create', 'list', 'ls', 'info', 'show', 'go', 'open',
        'remove', 'rm', 'delete', 'del', 'unregister', 'unreg',
        'edit', 'rename', 'ren', 'workspace', 'ws', 'copy', 'sync', 'color', 'clean',
        'host', 'agent', 'install', 'update', 'skill', 'sbx', 'help', 'run',
        'connect', 'conn', 'ssh',
        'sourcegit', 'sgit', 'sg',
        'chatgpt', 'cgpt', 'codex', 'droid', 'factory',
        'claude', 'cowork', 'claudecode', 'ccode',
        't3', 't3code', 'cmux', 'cm', 'wmux', 'wm',
        'ss', 'superset', 'supersetsh'
    )
    $family = foreach ($member in @(Get-WtwEditorFamily)) {
        foreach ($prefix in @($member.Prefixes)) { $prefix }
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @($core + @($family))) {
        if ($seen.Add($name)) { $names.Add($name) }
    }
    return $names
}

function Get-WtwCliPassthroughCommandNames {
    <#
    .SYNOPSIS
        CLI tokens wrappers must send to pwsh. Excludes ``go``, which cds in the parent shell.
    #>
    [CmdletBinding()]
    param()

    return @(Get-WtwCliCommandNames | Where-Object { $_ -ne 'go' })
}

function Get-WtwCliMutatingCommandNames {
    <#
    .SYNOPSIS
        Subcommands that can change registry or host lists; wrappers re-source aliases after them.
    #>
    [CmdletBinding()]
    param()

    return @(
        'init', 'add', 'create', 'remove', 'rm', 'delete', 'del',
        'unregister', 'unreg', 'edit', 'rename', 'ren', 'host'
    )
}
