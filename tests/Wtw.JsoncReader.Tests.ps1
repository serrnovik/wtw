BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    . "$PSScriptRoot/../private/Read-JsoncFile.ps1"
}

Describe 'Read-JsoncFile' {
    BeforeAll {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "wtw-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns null for non-existent file' {
        $result = Read-JsoncFile (Join-Path $script:tempDir 'nonexistent.json')
        $result | Should -BeNullOrEmpty
    }

    It 'reads valid JSON' {
        $file = Join-Path $script:tempDir 'valid.json'
        '{"key": "value"}' | Set-Content -Path $file
        $result = Read-JsoncFile $file
        $result.key | Should -Be 'value'
    }

    It 'strips trailing commas' {
        $file = Join-Path $script:tempDir 'trailing.json'
        '{"key": "value", "arr": [1, 2, 3,],}' | Set-Content -Path $file
        $result = Read-JsoncFile $file
        $result.key | Should -Be 'value'
        $result.arr.Count | Should -Be 3
    }

    It 'strips single-line comments' {
        $file = Join-Path $script:tempDir 'comments.json'
        @'
{
  // this is a comment
  "key": "value"
}
'@ | Set-Content -Path $file
        $result = Read-JsoncFile $file
        $result.key | Should -Be 'value'
    }

    It 'handles tilde in path' {
        $file = Join-Path $script:tempDir 'tilde.json'
        '{"ok": true}' | Set-Content -Path $file
        # Replace home dir with tilde
        $tildePath = $file.Replace($HOME, '~')
        $result = Read-JsoncFile $tildePath
        $result.ok | Should -BeTrue
    }
}
