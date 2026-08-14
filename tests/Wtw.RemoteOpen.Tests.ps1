BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }

    $script:winHost = @{
        Name = 'arctictroll'; Aliases = @('at'); User = 'sno'; HostName = '192.168.3.7'
        Port = $null; IdentityFile = $null; IdentitiesOnly = $false; Platform = 'windows'; Wtw = 'wtw'
    }
}

Describe 'Split-WtwOnHostArgs' {
    It 'strips a leading --on so the next token is still the subcommand' {
        # Invoke-Wtw dispatches on $args[0]; without this pre-scan `--on` would
        # be read as the command name.
        $result = Split-WtwOnHostArgs -ArgList @('--on', 'at', 'cursor', 'auth') -KnownHosts @('at')
        $result.Host | Should -Be 'at'
        $result.Args | Should -Be @('cursor', 'auth')
    }

    It 'strips a trailing --on' {
        $result = Split-WtwOnHostArgs -ArgList @('cursor', 'auth', '--on', 'at') -KnownHosts @('at')
        $result.Host | Should -Be 'at'
        $result.Args | Should -Be @('cursor', 'auth')
    }

    It 'treats a bare @token as an ordinary argument, not a host selector' {
        # PowerShell argument mode reads `@at` as splatting of $at, so the token
        # never survives to reach wtw. Supporting it would mean a command that
        # looks remote and silently runs locally.
        $result = Split-WtwOnHostArgs -ArgList @('cursor', 'auth', '@at') -KnownHosts @('at')
        $result.Host | Should -BeNullOrEmpty
        $result.Args | Should -Be @('cursor', 'auth', '@at')
    }

    It 'accepts a leading bare host when it is an exact known name' {
        $result = Split-WtwOnHostArgs -ArgList @('at', 'cursor', 'auth') -KnownHosts @('at', 'arctictroll')
        $result.Host | Should -Be 'at'
        $result.Args | Should -Be @('cursor', 'auth')
    }

    It 'does not treat a leading bare token as a host on a prefix match' {
        # A prefix could shadow a repo alias and silently open the wrong machine,
        # so the shorthand demands an exact host name.
        $result = Split-WtwOnHostArgs -ArgList @('arc', 'cursor') -KnownHosts @('arctictroll')
        $result.Host | Should -BeNullOrEmpty
        $result.Args | Should -Be @('arc', 'cursor')
    }

    It 'leaves a lone token alone even when it names a host' {
        # `wtw at` should still mean "go to the target called at", not a host
        # selector with no command.
        $result = Split-WtwOnHostArgs -ArgList @('at') -KnownHosts @('at')
        $result.Host | Should -BeNullOrEmpty
        $result.Args | Should -Be @('at')
    }

    It 'passes a plain local command list through untouched' {
        $result = Split-WtwOnHostArgs -ArgList @('create', 'auth', '--branch', 'main') -KnownHosts @('at')
        $result.Host | Should -BeNullOrEmpty
        $result.Args | Should -Be @('create', 'auth', '--branch', 'main')
    }

    It 'drops a dangling --on rather than swallowing the next flag' {
        $result = Split-WtwOnHostArgs -ArgList @('cursor', '--on') -KnownHosts @('at')
        $result.Host | Should -BeNullOrEmpty
        $result.Args | Should -Be @('cursor')
    }

    It 'tolerates no known hosts at all' {
        $result = Split-WtwOnHostArgs -ArgList @('cursor', 'auth') -KnownHosts @()
        $result.Host | Should -BeNullOrEmpty
        $result.Args | Should -Be @('cursor', 'auth')
    }

    It 'keeps an array-valued argument intact' {
        # PowerShell argument mode turns `--alias at,troll` into ONE array
        # argument. Splicing it here made the flag take 'at' and left 'troll' as
        # a stray positional that `wtw host add` silently discarded.
        $result = Split-WtwOnHostArgs -ArgList @('host', 'add', 'box', '--alias', @('at', 'troll')) -KnownHosts @()

        $result.Args.Count | Should -Be 5
        , $result.Args[4] | Should -BeOfType [System.Object[]]
        $result.Args[4] | Should -Be @('at', 'troll')
    }

    It 'keeps an array-valued argument intact while also extracting --on' {
        $result = Split-WtwOnHostArgs -ArgList @('--on', 'at', 'create', 'x', '--tags', @('a', 'b')) -KnownHosts @('at')

        $result.Host | Should -Be 'at'
        $result.Args.Count | Should -Be 4
        $result.Args[3] | Should -Be @('a', 'b')
    }
}

Describe 'Split-WtwAliasList' {
    # Compared as a joined string: the function returns `,@(...)` so the array
    # survives as one object, and piping that into Should compares the array
    # object itself rather than its elements.
    It 'accepts the array PowerShell produces for a bare at,troll' {
        (Split-WtwAliasList -Value @('at', 'troll')) -join '|' | Should -Be 'at|troll'
    }

    It 'accepts a quoted comma string' {
        (Split-WtwAliasList -Value @('at,troll')) -join '|' | Should -Be 'at|troll'
    }

    It 'trims and drops empties' {
        (Split-WtwAliasList -Value @(' at , , troll ')) -join '|' | Should -Be 'at|troll'
    }

    It 'returns an empty array for no input' {
        (Split-WtwAliasList -Value $null).Count | Should -Be 0
    }
}

Describe 'New-WtwRemoteScript' {
    It 'imports the module and calls Invoke-Wtw instead of the wtw command' {
        # On Windows `wtw` is the cmd.exe shim, which treats any subcommand it
        # does not know as a `go` target — that turned `wtw __aliases` into
        # 'could not resolve "__aliases"'.
        $script = New-WtwRemoteScript -Arguments @('__aliases')

        $script | Should -Match 'Import-Module'
        $script | Should -Match '\.wtw'
        $script | Should -Match "Invoke-Wtw '__aliases'"
        $script | Should -Not -Match '(?m)^\s*wtw\s'
    }

    It 'falls back to a PSGallery install when ~/.wtw/module is absent' {
        New-WtwRemoteScript -Arguments @('__aliases') | Should -Match 'Import-Module wtw'
    }

    It 'quotes arguments so a name with a quote cannot break out' {
        $script = New-WtwRemoteScript -Arguments @('__resolve_json', "it's-a-branch")
        $script | Should -Match "Invoke-Wtw '__resolve_json' 'it''s-a-branch'"
    }

    It 'honours an explicit wtw command override from the host config' {
        $script = New-WtwRemoteScript -Arguments @('__aliases') -WtwCommand 'D:\tools\wtw.ps1'
        $script | Should -Be "D:\tools\wtw.ps1 '__aliases'"
    }

    It 'ignores the default command name and still uses the module import' {
        New-WtwRemoteScript -Arguments @('__aliases') -WtwCommand 'wtw' | Should -Match 'Import-Module'
    }
}

Describe 'New-WtwRemotePwshCommand' {
    It 'calls pwsh plainly on a Windows remote' {
        # cmd.exe cannot run the POSIX probe loop, and pwsh is on PATH there.
        $cmd = New-WtwRemotePwshCommand -Encoded 'QUJD' -HostEntry @{ Name = 'w'; Platform = 'windows'; Pwsh = $null }
        $cmd -join ' ' | Should -Be 'pwsh -NoLogo -NoProfile -EncodedCommand QUJD'
    }

    It 'probes known install paths on a POSIX remote' {
        # `ssh host <cmd>` is a non-login, non-interactive shell: zsh reads only
        # ~/.zshenv, so Homebrew's PATH export in ~/.zprofile never runs and
        # /opt/homebrew/bin/pwsh is invisible.
        $cmd = New-WtwRemotePwshCommand -Encoded 'QUJD' -HostEntry @{ Name = 'm'; Platform = 'macos'; Pwsh = $null }

        $cmd.Count | Should -Be 1
        $cmd[0] | Should -Match '/opt/homebrew/bin/pwsh'
        $cmd[0] | Should -Match '/usr/local/bin/pwsh'
        $cmd[0] | Should -Match 'wtw-pwsh-not-found'
    }

    It 'leaves remote shell variables unexpanded' {
        # $c and $HOME belong to the remote shell; a double-quoted PowerShell
        # string would expand them to nothing before ssh saw them.
        $cmd = New-WtwRemotePwshCommand -Encoded 'QUJD' -HostEntry @{ Name = 'm'; Platform = 'macos'; Pwsh = $null }
        $cmd[0] | Should -Match 'command -v \$c'
        $cmd[0] | Should -Match '\$HOME/\.dotnet/tools/pwsh'
    }

    It 'contains no quote characters to be mangled in transit' {
        # The string crosses PowerShell binding, ssh argv joining and the remote
        # shell parser; every quote is another chance to be re-interpreted.
        $cmd = New-WtwRemotePwshCommand -Encoded 'QUJD' -HostEntry @{ Name = 'm'; Platform = 'macos'; Pwsh = $null }
        $cmd[0] | Should -Not -Match "['`"]"
    }

    It 'puts an explicit --pwsh path first' {
        $cmd = New-WtwRemotePwshCommand -Encoded 'QUJD' -HostEntry @{ Name = 'm'; Platform = 'macos'; Pwsh = '/custom/pwsh' }
        $cmd[0] | Should -Match 'for c in /custom/pwsh pwsh '
    }

    It 'honours an explicit path on Windows too' {
        $cmd = New-WtwRemotePwshCommand -Encoded 'QUJD' -HostEntry @{ Name = 'w'; Platform = 'windows'; Pwsh = 'C:\ps\pwsh.exe' }
        $cmd[0] | Should -Be 'C:\ps\pwsh.exe'
    }
}

Describe 'Get-WtwRemoteList' {
    BeforeEach {
        $script:sentArgs = $null
        Mock Invoke-WtwRemoteCommand {
            $script:sentArgs = $Arguments
            @{ Success = $true; Error = $null; Output = @('  Kind  Repo', "  repo  snowmain`r") }
        }
    }

    It 'delegates to the remote wtw list rather than reimplementing it' {
        # An earlier version parsed __aliases and drew its own table, so every
        # flag had to be re-supported by hand — `--detailed` was ignored.
        Get-WtwRemoteList -HostEntry $script:winHost | Out-Null
        $script:sentArgs[0] | Should -Be 'list'
    }

    It 'forwards flags verbatim so remote parsing matches local' {
        Get-WtwRemoteList -HostEntry $script:winHost -Arguments @('--detailed') | Out-Null
        $script:sentArgs | Should -Be @('list', '--detailed')

        Get-WtwRemoteList -HostEntry $script:winHost -Arguments @('--wide', '--repo', 'sn') | Out-Null
        $script:sentArgs | Should -Be @('list', '--wide', '--repo', 'sn')
    }

    It 'strips carriage returns from a Windows remote' {
        $out = Get-WtwRemoteList -HostEntry $script:winHost 6>&1 | Out-String
        $out | Should -Not -Match "`r`n`r"
    }
}

Describe 'Test-WtwRemoteCapableCommand' {
    It 'allows reads and VS Code family launches' {
        foreach ($cmd in 'open', 'list', 'ls', 'info', 'cursor', 'cur', 'code', 'co', 'windsurf', 'codium') {
            Test-WtwRemoteCapableCommand -Command $cmd | Should -BeTrue -Because "$cmd should work with --on"
        }
    }

    It 'rejects commands that mutate the remote registry' {
        # These must run on the machine that owns the worktree so its registry
        # stays authoritative.
        foreach ($cmd in 'create', 'remove', 'rm', 'color', 'sync', 'init', 'clean') {
            Test-WtwRemoteCapableCommand -Command $cmd | Should -BeFalse -Because "$cmd must run on the remote itself"
        }
    }

    It 'rejects launchers that register state in a locally running app' {
        foreach ($cmd in 'cmux', 'wmux', 't3', 'claudecode', 'ss', 'droid') {
            Test-WtwRemoteCapableCommand -Command $cmd | Should -BeFalse -Because "$cmd registers project state on the machine it runs on"
        }
    }

    It 'rejects go — there is no cd to another machine' {
        Test-WtwRemoteCapableCommand -Command 'go' | Should -BeFalse
    }
}

Describe 'Resolve-WtwRemoteLaunch' {
    It 'opens a remote workspace file via --file-uri' {
        $target = @{ Path = 'C:\repo_auth'; Workspace = 'C:\ws\auth.code-workspace'; Color = $null; Title = 'r/auth' }
        $launch = Resolve-WtwRemoteLaunch -Editor 'cursor' -HostEntry $script:winHost -RemoteTarget $target

        $launch.Kind | Should -Be 'workspace'
        $launch.PreArgs[0] | Should -Be '--file-uri'
        $launch.PreArgs[1] | Should -Be 'vscode-remote://ssh-remote+arctictroll/c:/ws/auth.code-workspace'
    }

    It 'falls back to --folder-uri when the remote has no workspace file' {
        $target = @{ Path = 'C:\repo_auth'; Workspace = $null; Color = $null; Title = 'r/auth' }
        $launch = Resolve-WtwRemoteLaunch -Editor 'cursor' -HostEntry $script:winHost -RemoteTarget $target

        $launch.Kind | Should -Be 'folder'
        $launch.PreArgs[0] | Should -Be '--folder-uri'
        $launch.PreArgs[1] | Should -Be 'vscode-remote://ssh-remote+arctictroll/c:/repo_auth'
    }

    It 'honours -Folder over an existing workspace file' {
        $target = @{ Path = 'C:\repo_auth'; Workspace = 'C:\ws\auth.code-workspace'; Color = $null; Title = 'r/auth' }
        $launch = Resolve-WtwRemoteLaunch -Editor 'code' -HostEntry $script:winHost -RemoteTarget $target -Folder

        $launch.Kind | Should -Be 'folder'
        $launch.PreArgs[0] | Should -Be '--folder-uri'
    }
}

Describe 'Invoke-WtwEditorCli remote invocation' {
    It 'puts the family launch flags before the remote URI' {
        Mock Test-WtwEditorCli { $true }
        $invocation = Invoke-WtwEditorCli -Cmd 'cursor' -PreArgs @('--folder-uri', 'vscode-remote://ssh-remote+at/c:/x') -PassThru

        $invocation.Arguments | Should -Be @('--new-window', '--folder-uri', 'vscode-remote://ssh-remote+at/c:/x')
    }

    It 'emits no bare path argument for a remote launch' {
        Mock Test-WtwEditorCli { $true }
        $invocation = Invoke-WtwEditorCli -Cmd 'code' -PreArgs @('--folder-uri', 'vscode-remote://ssh-remote+at/home/x') -PassThru

        $invocation.Arguments.Count | Should -Be 2
    }

    It 'refuses the .app bundle fallback for a remote launch' {
        # `open -a` can only carry a filesystem path, so silently falling back
        # would drop the remote authority and open a local phantom window.
        Mock Test-WtwEditorCli { $false }
        Mock Test-Path { $true }

        { Invoke-WtwEditorCli -Cmd 'cursor' -PreArgs @('--folder-uri', 'vscode-remote://ssh-remote+at/c:/x') -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*remote open needs the editor CLI*'
    }
}

Describe 'Open-WtwRemoteWorkspace' {
    # Open-WtwRemoteWorkspace is private, so these tests exercise the copy
    # dot-sourced into test scope by BeforeAll. Its callees resolve in that same
    # scope, which is why these mocks carry no -ModuleName: a module-scoped mock
    # would not intercept, and the real Get-WtwRemoteTarget would try to ssh.
    It 'refuses non-family editors with a pointer to running wtw remotely' {
        { Open-WtwRemoteWorkspace -HostEntry $script:winHost -Name 'auth' -Editor 't3' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*VS Code family*'
    }

    It 'launches the editor with the resolved remote URI' {
        Mock Get-WtwRemoteTarget {
            @{ Path = 'C:\repo_auth'; Workspace = $null; Color = '#123456'; Title = 'repo/auth'; PrettyName = 'Auth' }
        }
        Mock Invoke-WtwEditorCli {}

        Open-WtwRemoteWorkspace -HostEntry $script:winHost -Name 'auth' -Editor 'cursor' -SkipChecks

        Should -Invoke Invoke-WtwEditorCli -Times 1 -Exactly -ParameterFilter {
            $Cmd -eq 'cursor' -and
            $PreArgs[0] -eq '--folder-uri' -and
            $PreArgs[1] -eq 'vscode-remote://ssh-remote+arctictroll/c:/repo_auth'
        }
    }

    It 'opens the remote workspace file when the remote reports one' {
        Mock Get-WtwRemoteTarget {
            @{ Path = 'C:\repo_auth'; Workspace = 'C:\ws\auth.code-workspace'; Color = $null; Title = 'repo/auth'; PrettyName = $null }
        }
        Mock Invoke-WtwEditorCli {}

        Open-WtwRemoteWorkspace -HostEntry $script:winHost -Name 'auth' -Editor 'code' -SkipChecks

        Should -Invoke Invoke-WtwEditorCli -Times 1 -Exactly -ParameterFilter {
            $PreArgs[0] -eq '--file-uri' -and
            $PreArgs[1] -eq 'vscode-remote://ssh-remote+arctictroll/c:/ws/auth.code-workspace'
        }
    }

    It 'errors when the name does not resolve, without claiming it is missing' {
        # A connection failure lands here too, so the message must not assert
        # that the worktree does not exist over there.
        Mock Get-WtwRemoteTarget { $null }

        { Open-WtwRemoteWorkspace -HostEntry $script:winHost -Name 'ghost' -Editor 'cursor' -SkipChecks -ErrorAction Stop } |
            Should -Throw -ExpectedMessage "*Could not resolve 'ghost'*"
    }

    It 'does not launch anything under -PrintOnly' {
        Mock Get-WtwRemoteTarget {
            @{ Path = '/home/sno/repo'; Workspace = $null; Color = $null; Title = 'r/x'; PrettyName = $null }
        }
        Mock Invoke-WtwEditorCli { @{ Exe = 'cursor'; Arguments = $PreArgs } }

        Open-WtwRemoteWorkspace -HostEntry $script:winHost -Name 'x' -Editor 'cursor' -SkipChecks -PrintOnly

        Should -Invoke Invoke-WtwEditorCli -Times 1 -Exactly -ParameterFilter { $PassThru }
    }
}
