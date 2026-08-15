BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }

    $script:winHost = @{
        Name = 'workstation'; Aliases = @('at'); User = 'dev'; HostName = 'workstation.local'
        HostNames = @('workstation.local'); Port = $null; Platform = 'windows'; Wtw = 'wtw'; Pwsh = $null
    }
}

Describe 'Get-WtwRemoteCommandMode — connect' {
    It 'maps go and its synonyms to an interactive session' {
        # `go` means "be in that worktree". Over ssh that is achievable, so it
        # connects rather than being refused.
        foreach ($cmd in 'go', 'connect', 'conn', 'ssh') {
            Get-WtwRemoteCommandMode -Command $cmd | Should -Be 'connect'
        }
    }
}

Describe 'Get-WtwHostTitlePrefix' {
    It 'uses the configured emoji and label' {
        $h = @{ Name = 'workstation'; Aliases = @('at'); Emoji = '#'; Label = 'AT' }
        Get-WtwHostTitlePrefix -HostEntry $h | Should -Be '#AT.'
    }

    It 'falls back to the shortest alias, upper-cased' {
        # Useful without configuring anything.
        $h = @{ Name = 'workstation'; Aliases = @('troll', 'at'); Emoji = $null; Label = $null }
        Get-WtwHostTitlePrefix -HostEntry $h | Should -Be 'AT.'
    }

    It 'falls back to the first two letters when there is no alias' {
        $h = @{ Name = 'buildbox'; Aliases = @(); Emoji = $null; Label = $null }
        Get-WtwHostTitlePrefix -HostEntry $h | Should -Be 'BU.'
    }

    It 'omits the emoji rather than inventing one' {
        # An auto-assigned per-machine emoji would be noise, not identity.
        $h = @{ Name = 'workstation'; Aliases = @('at'); Emoji = $null; Label = 'AT' }
        Get-WtwHostTitlePrefix -HostEntry $h | Should -Be 'AT.'
    }

    It 'keeps an explicit label even when aliases exist' {
        $h = @{ Name = 'workstation'; Aliases = @('at', 'x'); Emoji = $null; Label = 'WORK' }
        Get-WtwHostTitlePrefix -HostEntry $h | Should -Be 'WORK.'
    }
}

Describe 'Remote session title composition' {
    It 'prefixes the machine, then the worktree pretty name' {
        # prettyName already carries the worktree's own emoji, so the remote tab
        # reads like the local one for that worktree plus a machine prefix.
        Mock Get-WtwRemoteTarget {
            @{ Path = 'E:\repos\app'; Workspace = $null; Color = '#336699'
                Title = 'app/PF037'; PrettyName = 'PF037 gamification'
            }
        }
        $h = $script:winHost.Clone(); $h.Emoji = '#'; $h.Label = 'AT'

        $out = Connect-WtwRemoteWorktree -HostEntry $h -Name 'PF037' -PrintOnly 6>&1 | Out-String
        $encoded = [regex]::Match($out, '-EncodedCommand ([A-Za-z0-9+/=]+)').Groups[1].Value
        $decoded = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))

        $decoded | Should -Match "WindowTitle = '#AT.PF037 gamification'"
    }

    It 'falls back to repo/task when the worktree has no pretty name' {
        Mock Get-WtwRemoteTarget {
            @{ Path = 'E:\repos\app'; Workspace = $null; Color = $null; Title = 'app/auth'; PrettyName = $null }
        }
        $h = $script:winHost.Clone(); $h.Emoji = $null; $h.Label = 'AT'

        $out = Connect-WtwRemoteWorktree -HostEntry $h -Name 'auth' -PrintOnly 6>&1 | Out-String
        $encoded = [regex]::Match($out, '-EncodedCommand ([A-Za-z0-9+/=]+)').Groups[1].Value
        $decoded = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))

        $decoded | Should -Match "WindowTitle = 'AT.app/auth'"
    }
}

Describe 'Show-WtwRemoteTargetSuggestions' {
    BeforeEach {
        Mock Invoke-WtwRemoteCommand {
            @{
                Success = $true; Error = $null
                Output  = @(
                    "sn`tE:\repos\app`t#1a1ad5`tapp`t`t`t0"
                    "sn-PF037_work`tE:\repos\app_PF037`t#008000`tapp/PF037_work`t`tPF037_work`t1"
                    "kl-demo-1`tE:\repos\demo`t#ffff00`tdemo/demo-1`t`tdemo-1`t1"
                )
            }
        }
    }

    It 'lists what the machine actually has when nothing matches' {
        # "run wtw list" is fine locally and useless across a network — you
        # cannot glance at the other machine's registry.
        $out = Show-WtwRemoteTargetSuggestions -HostEntry $script:winHost -Name 'zzqq' 6>&1 | Out-String
        $out | Should -Match "Nothing on workstation matches 'zzqq'"
        $out | Should -Match 'sn-PF037_work'
    }

    It 'finds a near-miss issue number by token, not whole-string distance' {
        # 'PF033' is ~30 edits from 'sn-PF037_work' as whole strings, so the
        # normal fuzzy pass cannot see it — but it is ONE edit from that name's
        # 'PF037' token, which is the actual mistake.
        $out = Show-WtwRemoteTargetSuggestions -HostEntry $script:winHost -Name 'PF033' 6>&1 | Out-String
        $out | Should -Match 'Closest on workstation'
        $out | Should -Match 'sn-PF037_work'
        $out | Should -Not -Match 'kl-demo-1'
    }

    It 'narrows to matches on the digits when the name is an issue number' {
        # A wrong issue number is the common case; "here are the ones with 037"
        # is the useful reply.
        $out = Show-WtwRemoteTargetSuggestions -HostEntry $script:winHost -Name 'PF037' 6>&1 | Out-String
        $out | Should -Match 'Closest on workstation'
        $out | Should -Match 'sn-PF037_work'
        $out | Should -Not -Match 'kl-demo-1'
    }

    It 'stays silent when the remote could not be reached' {
        Mock Invoke-WtwRemoteCommand { @{ Success = $false; Error = 'Connection refused'; Output = @() } }
        $out = Show-WtwRemoteTargetSuggestions -HostEntry $script:winHost -Name 'x' 6>&1 | Out-String
        $out.Trim() | Should -BeNullOrEmpty
    }
}

Describe 'Get-WtwNumericNameHint' {
    It 'explains an all-digit name' {
        # `wtw go 033` reaches wtw as the integer 33: PowerShell's argument mode
        # parses the bare token as a number and the leading zero is gone before
        # wtw is called, so it can only be explained, never recovered.
        $hint = Get-WtwNumericNameHint -Name '33'
        $hint | Should -Match "quote it: '033'"
    }

    It 'says nothing for an ordinary name' {
        Get-WtwNumericNameHint -Name 'PF037'   | Should -BeNullOrEmpty
        Get-WtwNumericNameHint -Name 'auth'    | Should -BeNullOrEmpty
        Get-WtwNumericNameHint -Name 'sn-037'  | Should -BeNullOrEmpty
        Get-WtwNumericNameHint -Name ''        | Should -BeNullOrEmpty
    }
}

Describe 'Test-WtwIsLocalMachine' {
    It 'recognises this machine by hostname, case-insensitively' {
        $names = Get-WtwLocalMachineName
        $names.Count | Should -BeGreaterThan 0

        Test-WtwIsLocalMachine -Name $names[0]              | Should -BeTrue
        Test-WtwIsLocalMachine -Name $names[0].ToUpperInvariant() | Should -BeTrue
    }

    It 'does not claim an unrelated name' {
        Test-WtwIsLocalMachine -Name 'some-other-box' | Should -BeFalse
    }

    It 'returns a flat list of names, not a nested array' {
        # Get-WtwLocalMachineName returns `,@(...)`; a caller that re-wraps it
        # gets [0] = the whole array, which printed every name in the error.
        $names = Get-WtwLocalMachineName
        $names[0] | Should -BeOfType [string]
    }

    It 'takes only the self entry from the tailnet, not every peer' {
        # Piping a `,@(...)` return straight into Where-Object hands it the array
        # as ONE item, so `$_.IsSelf` is an array of booleans and every peer
        # "matches" — which listed the whole tailnet as "this machine".
        $names = Get-WtwLocalMachineName
        $names.Count | Should -BeLessThan 6
    }
}

Describe 'New-WtwRemotePwshCommand -Interactive' {
    It 'adds -NoExit so the shell survives the payload' {
        $cmd = New-WtwRemotePwshCommand -Encoded 'QUJD' -HostEntry $script:winHost -Interactive
        $cmd | Should -Contain '-NoExit'
    }

    It 'keeps the remote profile for an interactive session' {
        # The point is to land in the shell you would get by hand — prompt,
        # aliases and all. Scripted calls still use -NoProfile.
        $cmd = New-WtwRemotePwshCommand -Encoded 'QUJD' -HostEntry $script:winHost -Interactive
        $cmd | Should -Not -Contain '-NoProfile'

        $scripted = New-WtwRemotePwshCommand -Encoded 'QUJD' -HostEntry $script:winHost
        $scripted | Should -Contain '-NoProfile'
        $scripted | Should -Not -Contain '-NoExit'
    }

    It 'carries the interactive flags into the POSIX probe loop too' {
        $posix = @{ Name = 'box'; Platform = 'linux'; Pwsh = $null }
        $cmd = New-WtwRemotePwshCommand -Encoded 'QUJD' -HostEntry $posix -Interactive
        $cmd[0] | Should -Match '-NoLogo -NoExit -EncodedCommand QUJD'
        $cmd[0] | Should -Not -Match '-NoProfile'
    }
}

Describe 'Connect-WtwRemoteWorktree' {
    BeforeEach {
        Mock Get-WtwRemoteTarget {
            @{ Path = 'E:\repos\app_auth'; Workspace = $null; Color = '#336699'; Title = 'app/auth'; PrettyName = 'Auth' }
        }
    }

    It 'forces a TTY — without it pwsh exits immediately' {
        $out = Connect-WtwRemoteWorktree -HostEntry $script:winHost -Name 'auth' -PrintOnly 6>&1 | Out-String
        $out | Should -Match 'ssh -t workstation'
    }

    It 'sends the target path as an encoded payload, never as raw argv' {
        # A path with spaces or quotes has to survive the local shell, ssh argv
        # joining and cmd.exe on the far side.
        $out = Connect-WtwRemoteWorktree -HostEntry $script:winHost -Name 'auth' -PrintOnly 6>&1 | Out-String
        $out | Should -Match '-EncodedCommand [A-Za-z0-9+/=]+'
        $out | Should -Not -Match 'E:\\repos\\app_auth'
    }

    It 'decodes to a payload that sets the title and cds to the worktree' {
        $out = Connect-WtwRemoteWorktree -HostEntry $script:winHost -Name 'auth' -PrintOnly 6>&1 | Out-String
        $encoded = [regex]::Match($out, '-EncodedCommand ([A-Za-z0-9+/=]+)').Groups[1].Value
        $decoded = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))

        $decoded | Should -Match "WindowTitle = 'AT.Auth'"
        $decoded | Should -Match "Set-Location -LiteralPath"
        $decoded | Should -Match 'E:\\repos\\app_auth'
    }

    It 'guards the cd so a stale registry entry does not strand the session' {
        # A worktree deleted without unregistering is normal; without the guard
        # you land in the home directory with a red error scrolled off the top.
        $out = Connect-WtwRemoteWorktree -HostEntry $script:winHost -Name 'auth' -PrintOnly 6>&1 | Out-String
        $encoded = [regex]::Match($out, '-EncodedCommand ([A-Za-z0-9+/=]+)').Groups[1].Value
        $decoded = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))

        $decoded | Should -Match 'Test-Path -LiteralPath'
        $decoded | Should -Match 'does not exist on this machine'
    }

    It 'connects to the host itself when no target is given' {
        $out = Connect-WtwRemoteWorktree -HostEntry $script:winHost -PrintOnly 6>&1 | Out-String
        $out | Should -Match 'ssh -t workstation'

        $encoded = [regex]::Match($out, '-EncodedCommand ([A-Za-z0-9+/=]+)').Groups[1].Value
        $decoded = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
        $decoded | Should -Not -Match 'Set-Location'
        $decoded | Should -Match "WindowTitle = 'AT.workstation'"
    }

    It 'escapes a quote in the remote path' {
        Mock Get-WtwRemoteTarget {
            @{ Path = "E:\it's\repo"; Workspace = $null; Color = $null; Title = 'x'; PrettyName = $null }
        }
        $out = Connect-WtwRemoteWorktree -HostEntry $script:winHost -Name 'x' -PrintOnly 6>&1 | Out-String
        $encoded = [regex]::Match($out, '-EncodedCommand ([A-Za-z0-9+/=]+)').Groups[1].Value
        $decoded = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))

        $decoded | Should -Match "E:\\it''s\\repo"
    }

    It 'errors without launching ssh when the name does not resolve' {
        Mock Get-WtwRemoteTarget { $null }
        { Connect-WtwRemoteWorktree -HostEntry $script:winHost -Name 'ghost' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage "*Could not resolve 'ghost'*"
    }
}
