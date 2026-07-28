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
