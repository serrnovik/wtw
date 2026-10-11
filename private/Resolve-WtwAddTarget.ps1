function Resolve-WtwAddTarget {
    <#
    .SYNOPSIS
        Turn `wtw add` arguments into a worktree directory and task name.
    .DESCRIPTION
        The positional argument is a path. A bare token that is not a path,
        typed from inside an existing worktree, is the registry task instead
        (`wtw add update-routine` == `wtw add . --task update-routine`).
    #>
    param(
        [string] $Path,
        [string] $Task
    )

    if (-not $Path) {
        return @{ Path = (Get-Location).Path; Task = $Task }
    }

    $bareName = ($Path -notmatch '[\\/]') -and ($Path -notin @('.', '..'))
    if ($bareName -and -not (Test-Path -LiteralPath $Path)) {
        $cwd = (Get-Location).Path
        $cwdGit = Join-Path $cwd '.git'
        if (Test-Path -LiteralPath $cwdGit -PathType Leaf) {
            if ($Task -and $Task -ne $Path) {
                Write-Error "Path does not exist: $Path. From inside a worktree pass the directory, or one task name (not both '$Path' and --task $Task)."
                return $null
            }
            if (-not $Task) { $Task = $Path }
            return @{ Path = $cwd; Task = $Task }
        }
    }

    try {
        $Path = [System.IO.Path]::GetFullPath($Path)
    } catch {
        Write-Error "Path does not exist: $Path"
        return $null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Error @"
Path does not exist: $Path
wtw add adopts a worktree that is already on disk. It does not create one.
  From inside that worktree:  wtw add <task> [--emoji ...]
                               wtw add --task <task>
  To create a new worktree:   wtw create <task>
"@
        return $null
    }

    return @{ Path = $Path; Task = $Task }
}
