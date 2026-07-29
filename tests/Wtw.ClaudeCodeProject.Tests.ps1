BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'New-WtwClaudeCodeDeepLink' {
    It 'roots a new chat at the absolute project directory' {
        $url = New-WtwClaudeCodeDeepLink -ProjectPath ([System.IO.Path]::GetTempPath())

        $uri = [uri] $url
        $uri.Scheme | Should -Be 'claude'
        $uri.Host | Should -Be 'code'
        $uri.AbsolutePath | Should -Be '/new'
    }

    It 'percent-encodes paths containing spaces' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) 'wtw dir with spaces'
        $url = New-WtwClaudeCodeDeepLink -ProjectPath $dir

        $url | Should -Not -Match '\s'
        $url | Should -Match 'folder=[^&]*%20'
    }

    It 'omits the composer seed when no prompt is given' {
        $url = New-WtwClaudeCodeDeepLink -ProjectPath ([System.IO.Path]::GetTempPath())

        $url | Should -Not -Match '(\?|&)q='
    }

    It 'passes a prompt through as the q parameter' {
        $url = New-WtwClaudeCodeDeepLink -ProjectPath ([System.IO.Path]::GetTempPath()) -Prompt 'review & ship'

        $query = ([uri] $url).Query.TrimStart('?')
        $q = ($query -split '&' | Where-Object { $_ -like 'q=*' }) -replace '^q=', ''
        [uri]::UnescapeDataString($q) | Should -Be 'review & ship'
    }

    It 'truncates an over-long prompt to the app''s composer cap' {
        $url = New-WtwClaudeCodeDeepLink -ProjectPath ([System.IO.Path]::GetTempPath()) -Prompt ('x' * 20000)

        $query = ([uri] $url).Query.TrimStart('?')
        $q = ($query -split '&' | Where-Object { $_ -like 'q=*' }) -replace '^q=', ''
        [uri]::UnescapeDataString($q).Length | Should -Be 14000
    }
}

Describe 'Set-WtwClaudeCodeProjectTrust' {
    BeforeEach {
        $script:cfgDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-claudecfg-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:cfgDir | Out-Null
        $script:cfg = Join-Path $script:cfgDir '.claude.json'
        $env:CLAUDE_CONFIG_DIR = $script:cfgDir
    }
    AfterEach {
        $env:CLAUDE_CONFIG_DIR = $null
        Remove-Item -Recurse -Force $script:cfgDir -ErrorAction SilentlyContinue
    }

    It 'no-ops when Claude Code has no config file' {
        Set-WtwClaudeCodeProjectTrust -ProjectPath '/tmp/some-worktree' | Should -BeNullOrEmpty
        Test-Path $script:cfg | Should -BeFalse
    }

    It 'pre-accepts the trust prompt for a new project' {
        '{"numStartups":3,"projects":{}}' | Set-Content -Path $script:cfg -NoNewline

        $result = Set-WtwClaudeCodeProjectTrust -ProjectPath '/tmp/new-worktree'

        $result | Should -Be '/tmp/new-worktree'
        $saved = Get-Content $script:cfg -Raw | ConvertFrom-Json
        $saved.projects.'/tmp/new-worktree'.hasTrustDialogAccepted | Should -BeTrue
        $saved.numStartups | Should -Be 3   # unrelated top-level state survives
    }

    It 'preserves existing project state and nesting deeper than the default JSON depth' {
        $existing = @{
            projects = @{
                '/tmp/existing' = @{
                    hasTrustDialogAccepted = $false
                    allowedTools           = @('Bash')
                    deep                   = @{ a = @{ b = @{ c = @{ d = 'kept' } } } }
                }
            }
        } | ConvertTo-Json -Depth 100
        $existing | Set-Content -Path $script:cfg -NoNewline

        Set-WtwClaudeCodeProjectTrust -ProjectPath '/tmp/existing' | Should -Be '/tmp/existing'

        $saved = Get-Content $script:cfg -Raw | ConvertFrom-Json
        $saved.projects.'/tmp/existing'.hasTrustDialogAccepted | Should -BeTrue
        $saved.projects.'/tmp/existing'.allowedTools | Should -Be @('Bash')
        $saved.projects.'/tmp/existing'.deep.a.b.c.d | Should -Be 'kept'
    }

    It 'leaves the file byte-identical when the project is already trusted' {
        '{"projects":{"/tmp/trusted":{"hasTrustDialogAccepted":true}}}' | Set-Content -Path $script:cfg -NoNewline
        $before = Get-Content $script:cfg -Raw

        Set-WtwClaudeCodeProjectTrust -ProjectPath '/tmp/trusted' | Should -Be '/tmp/trusted'

        Get-Content $script:cfg -Raw | Should -Be $before
    }

    It 'removes only the requested project entry' {
        '{"projects":{"/tmp/a":{"hasTrustDialogAccepted":true},"/tmp/b":{"hasTrustDialogAccepted":true}}}' |
            Set-Content -Path $script:cfg -NoNewline

        Set-WtwClaudeCodeProjectTrust -ProjectPath '/tmp/a' -Remove | Should -Be '/tmp/a'

        $saved = Get-Content $script:cfg -Raw | ConvertFrom-Json
        (Get-WtwPropertyNames -Object $saved.projects) | Should -Be @('/tmp/b')
    }

    It 'no-ops on removal when the project was never registered' {
        '{"projects":{"/tmp/b":{"hasTrustDialogAccepted":true}}}' | Set-Content -Path $script:cfg -NoNewline
        $before = Get-Content $script:cfg -Raw

        Set-WtwClaudeCodeProjectTrust -ProjectPath '/tmp/a' -Remove | Should -BeNullOrEmpty

        Get-Content $script:cfg -Raw | Should -Be $before
    }

    It 'leaves the config untouched when it is not valid JSON' {
        'not json at all' | Set-Content -Path $script:cfg -NoNewline

        Set-WtwClaudeCodeProjectTrust -ProjectPath '/tmp/x' -WarningAction SilentlyContinue |
            Should -BeNullOrEmpty

        Get-Content $script:cfg -Raw | Should -Be 'not json at all'
        # no half-written temp file left behind
        @(Get-ChildItem $script:cfgDir -Filter '*.tmp').Count | Should -Be 0
    }
}

Describe 'Start-WtwClaudeCodeSession' -Skip:(-not $IsMacOS) {
    It 'sends the deep link once when the app is already running' {
        Mock Get-WtwClaudeMacAppName { 'Claude' }
        Mock Test-WtwClaudeAppRunning { $true }
        Mock open {}
        Mock Start-Sleep { throw 'a warm app must not be slept on' }

        $result = Start-WtwClaudeCodeSession -ProjectPath ([System.IO.Path]::GetTempPath())

        $result.Success | Should -BeTrue
        Should -Invoke open -Times 1 -Exactly
    }

    It 'launches the app and re-sends the link on cold start' {
        # The app's URL handler drops deep links while its main webContents is
        # still detached, so a cold start needs a launch + settle + repeat.
        Mock Get-WtwClaudeMacAppName { 'Claude' }
        Mock Test-WtwClaudeAppRunning { $false }
        Mock open {}
        Mock Start-Sleep {}

        $result = Start-WtwClaudeCodeSession -ProjectPath ([System.IO.Path]::GetTempPath()) -LaunchTimeoutSeconds 0 6>$null

        $result.Success | Should -BeTrue
        # 1 launch (`open -a Claude`) + 2 deep-link sends
        Should -Invoke open -Times 3 -Exactly
    }

    It 'reports a missing install instead of dispatching the url' {
        Mock Get-WtwClaudeMacAppName { $null }
        Mock open { throw 'must not dispatch without an installed app' }

        $result = Start-WtwClaudeCodeSession -ProjectPath ([System.IO.Path]::GetTempPath())

        $result.Success | Should -BeFalse
        $result.Reason | Should -Match 'not installed'
        Should -Invoke open -Times 0
    }
}

Describe 'Open-WtwClaudeCodeWorkspace' {
    BeforeAll {
        $script:tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-claudecode-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:tmp | Out-Null
    }
    AfterAll {
        Remove-Item -Recurse -Force $script:tmp -ErrorAction SilentlyContinue
    }

    It 'reports the launch failure reason instead of claiming success' {
        Mock Start-WtwClaudeCodeSession {
            [PSCustomObject]@{ Success = $false; Url = 'claude://code/new'; Reason = 'Claude for Desktop is not installed. Tried: Claude.app' }
        } -ModuleName wtw

        $target = [PSCustomObject]@{
            RepoName      = 'sample'
            TaskName      = 'missing-app'
            WorktreeEntry = [PSCustomObject]@{ path = $script:tmp }
            RepoEntry     = [PSCustomObject]@{ mainPath = $script:tmp }
        }

        { Open-WtwClaudeCodeWorkspace -Target $target -ErrorAction Stop } |
            Should -Throw '*not installed*'
    }

    It 'falls back to the repo main path when the target has no worktree' {
        Mock Start-WtwClaudeCodeSession {
            [PSCustomObject]@{ Success = $true; Url = 'claude://code/new'; Reason = $null }
        } -ModuleName wtw

        $target = [PSCustomObject]@{
            RepoName      = 'sample'
            TaskName      = $null
            WorktreeEntry = $null
            RepoEntry     = [PSCustomObject]@{ mainPath = $script:tmp }
        }

        Open-WtwClaudeCodeWorkspace -Target $target 6>$null

        Should -Invoke Start-WtwClaudeCodeSession -ModuleName wtw -Times 1 -Exactly -ParameterFilter {
            $ProjectPath -eq $script:tmp
        }
    }
}
