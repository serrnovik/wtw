function Split-WtwOnHostArgs {
    <#
    .SYNOPSIS
        Extract the target host from a raw wtw argument list.
    .DESCRIPTION
        Invoke-Wtw dispatches on $args[0], so a leading `--on` would be read as
        the subcommand. This runs first and strips the host selector wherever it
        appears, leaving a normal argument list behind.

        Two accepted forms:
          wtw --on at cursor auth     explicit, position-independent
                                      (`--at` is an alias of `--on`)
          wtw at cursor auth          shorthand — only when the first token is a
                                      known host AND something follows it

        The shorthand is deliberately the most conservative: it requires an exact
        host name or alias, never a prefix, because a prefix could shadow a repo
        alias and silently send you to the wrong machine. `--on` itself does
        allow prefix resolution, since there the intent is unambiguous.

        There is deliberately no `@host` form: PowerShell's argument mode reads a
        bare `@at` as splatting of `$at`, so an undefined variable makes the token
        vanish before wtw is even called — the request would silently run locally.
    .PARAMETER ArgList
        Raw arguments as received by Invoke-Wtw.
    .PARAMETER KnownHosts
        Flat list of host names and aliases (Get-WtwHostNames). Passed in rather
        than read from config so this stays a pure function.
    .OUTPUTS
        @{ Host = <string|$null>; Args = <object[]> }
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] [object[]] $ArgList,
        [AllowNull()] [string[]] $KnownHosts
    )

    $remaining = @()
    $targetHost = $null
    $items = @($ArgList)
    $i = 0

    while ($i -lt $items.Count) {
        $arg = "$($items[$i])"

        # `--at` is an accepted spelling of `--on`; both read naturally against a
        # host name ("--on at" / "--at at"). Nothing else in wtw claims either
        # token, and no parameter starts with "At", so PowerShell prefix matching
        # cannot turn `-at` into something else.
        if ($arg -ieq '--on' -or $arg -ieq '-on' -or $arg -ieq '--at' -or $arg -ieq '-at') {
            if (($i + 1) -lt $items.Count) {
                $targetHost = "$($items[$i + 1])"
                $i += 2
                continue
            }
            # Dangling selector — drop it and let the caller report a missing host.
            $i++
            continue
        }

        # Comma operator, not a bare +=. PowerShell argument mode turns
        # `--alias at,troll` into ONE array-valued argument, and `+=` would
        # splice it into two tokens — the flag would take 'at' and 'troll' would
        # silently become a stray positional. This pre-scan must be transparent
        # to every argument shape it does not consume.
        $remaining += , $items[$i]
        $i++
    }

    # Leading bare host: `wtw at cursor auth`. Exact match only.
    if (-not $targetHost -and $remaining.Count -ge 2 -and $KnownHosts) {
        $first = "$($remaining[0])"
        if ($KnownHosts -contains $first) {
            $targetHost = $first
            $remaining = @($remaining[1..($remaining.Count - 1)])
        }
    }

    return @{ Host = $targetHost; Args = @($remaining) }
}

function Remove-WtwFlagWithValue {
    <#
    .SYNOPSIS
        Drop a `--flag value` pair from a raw argument list.
    .DESCRIPTION
        Local-only flags must not reach the remote CLI. `wtw --on at list --via lan`
        forwards its flags verbatim so the remote's own parser handles
        `--detailed` and friends — but `--via` is consumed here, and the remote
        `wtw list` has no such parameter, so leaving it in makes the whole command
        fail on the far side.
    .PARAMETER ArgList
        Raw tokens.
    .PARAMETER Flag
        Flag name without dashes, matched case-insensitively.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] [object[]] $ArgList,
        [Parameter(Mandatory)] [string] $Flag
    )

    $items = @($ArgList)
    $kept = @()
    $i = 0
    while ($i -lt $items.Count) {
        $token = "$($items[$i])"
        if ($token -ieq "--$Flag" -or $token -ieq "-$Flag") {
            # Skip the flag and its value, if the next token is not another flag.
            $i++
            if ($i -lt $items.Count -and "$($items[$i])" -notmatch '^-') { $i++ }
            continue
        }
        $kept += , $items[$i]
        $i++
    }
    return , @($kept)
}

# Commands that mutate the remote's own registry. They are not refused — they
# are executed ON the remote, which is what keeps its registry authoritative.
$script:WtwRemoteExecCommands = @(
    'run', 'create', 'add', 'remove', 'rm', 'delete', 'del', 'sync', 'color',
    'clean', 'init', 'workspace', 'ws', 'copy', 'unregister', 'unreg', 'install', 'update'
)

function Get-WtwRemoteCommandMode {
    <#
    .SYNOPSIS
        How a subcommand should be handled when `--on` is present.
    .DESCRIPTION
        Four outcomes:

          local    interpreted here — a read whose result we render, or a VS Code
                   editor launch where the window is local and the files remote.
          exec     forwarded verbatim and executed on the remote machine.
          connect  an interactive ssh session inside the remote worktree.
          none     refused, because no reading of it makes sense.

        `go` maps to connect rather than being refused: the verb means "be in
        that worktree", and over ssh that is exactly what it can do. The
        app-launchers (t3, cmux, claudecode, chatgpt…) stay refused because they
        are ambiguous rather than impossible — "register that project over there"
        is meaningful — so they are reachable through the explicit `run`, where
        the intent is stated rather than guessed.
    .OUTPUTS
        'local' | 'exec' | 'connect' | 'none'
    #>
    [CmdletBinding()]
    param([AllowNull()] [string] $Command)

    if (-not $Command) { return 'none' }
    if ($Command -in @('go', 'connect', 'conn', 'ssh')) { return 'connect' }
    if ($Command -in @('open', 'list', 'ls', 'info', 'show')) { return 'local' }
    if (Resolve-WtwEditorFamilyMember -Name $Command) { return 'local' }
    if ($Command -in $script:WtwRemoteExecCommands) { return 'exec' }
    return 'none'
}

function Test-WtwRemoteCapableCommand {
    <#
    .SYNOPSIS
        Can this subcommand be used with --on at all?
    #>
    [CmdletBinding()]
    param([AllowNull()] [string] $Command)

    return ((Get-WtwRemoteCommandMode -Command $Command) -ne 'none')
}
