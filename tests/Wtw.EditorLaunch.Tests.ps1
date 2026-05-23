BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Test-WtwEditorCli' {
    BeforeAll {
        $script:tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-cli-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:tmp | Out-Null
    }
    AfterAll {
        Remove-Item -Recurse -Force $script:tmp -ErrorAction SilentlyContinue
    }

    It 'returns $false for a command that is not on PATH' {
        Test-WtwEditorCli -Cmd 'wtw-totally-missing-editor-xyz' | Should -BeFalse
    }

    It 'returns $false for a dangling symlink on PATH' {
        $missingTarget = Join-Path $script:tmp 'gone'
        $linkDir = Join-Path $script:tmp 'bin'
        New-Item -ItemType Directory -Path $linkDir | Out-Null
        $link = Join-Path $linkDir 'wtw-dangling-editor'
        New-Item -ItemType SymbolicLink -Path $link -Target $missingTarget | Out-Null
        $oldPath = $env:PATH
        try {
            $env:PATH = "$linkDir$([System.IO.Path]::PathSeparator)$oldPath"
            Test-WtwEditorCli -Cmd 'wtw-dangling-editor' | Should -BeFalse
        } finally {
            $env:PATH = $oldPath
        }
    }

    It 'returns $true for a real executable on PATH' {
        $realDir = Join-Path $script:tmp 'real'
        New-Item -ItemType Directory -Path $realDir | Out-Null
        $exe = Join-Path $realDir 'wtw-real-editor'
        Set-Content -Path $exe -Value "#!/bin/sh`necho hi" -NoNewline
        if (-not $IsWindows) { chmod +x $exe }
        $oldPath = $env:PATH
        try {
            $env:PATH = "$realDir$([System.IO.Path]::PathSeparator)$oldPath"
            Test-WtwEditorCli -Cmd 'wtw-real-editor' | Should -BeTrue
        } finally {
            $env:PATH = $oldPath
        }
    }
}

Describe 'Invoke-WtwEditorCli' {
    It 'prefers the renamed antigravity-ide CLI over the legacy antigravity stub' {
        $script:queried = [System.Collections.Generic.List[string]]::new()
        Mock Test-WtwEditorCli { $script:queried.Add($Cmd); $false }
        Mock Test-Path { $false }   # no mac app bundle either

        Invoke-WtwEditorCli -Cmd 'antigravity' -Path '/tmp/x' -ErrorAction SilentlyContinue 2>$null

        $script:queried[0] | Should -Be 'antigravity-ide'
        $script:queried   | Should -Contain 'antigravity'
    }

    It 'errors when no candidate is runnable and no app bundle exists' {
        Mock Test-WtwEditorCli { $false }
        Mock Test-Path { $false }

        { Invoke-WtwEditorCli -Cmd 'antigravity' -Path '/tmp/x' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*not runnable*'
    }
}
