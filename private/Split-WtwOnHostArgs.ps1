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

        if ($arg -ieq '--on' -or $arg -ieq '-on') {
            if (($i + 1) -lt $items.Count) {
                $targetHost = "$($items[$i + 1])"
                $i += 2
                continue
            }
            # Dangling `--on` — drop it and let the caller report a missing host.
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

function Test-WtwRemoteCapableCommand {
    <#
    .SYNOPSIS
        Can this subcommand run against a remote host?
    .DESCRIPTION
        Only reads and editor launches cross the network. `go` cannot cd to
        another machine; `create` / `remove` / `color` / `sync` mutate state that
        belongs to the remote wtw and should be run there (over ssh, by you) so
        its registry stays authoritative; `cmux` / `t3` / `claudecode` register
        project state in an app running on that machine, so a local launch would
        point the wrong app at an unreachable path.
    #>
    [CmdletBinding()]
    param([AllowNull()] [string] $Command)

    if (-not $Command) { return $false }
    if ($Command -in @('open', 'list', 'ls', 'info', 'show')) { return $true }

    $member = Resolve-WtwEditorFamilyMember -Name $Command
    return [bool]$member
}
