BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking

    $script:testRoot = Join-Path ([IO.Path]::GetTempPath()) ('wtw-eol-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:testRoot -Force | Out-Null

    function Get-WtwEolCounts {
        param([string] $Path)
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $crlf = 0
        $lf = 0
        for ($i = 0; $i -lt $bytes.Length; $i++) {
            if ($bytes[$i] -eq 13 -and $i + 1 -lt $bytes.Length -and $bytes[$i + 1] -eq 10) {
                $crlf++
            } elseif ($bytes[$i] -eq 10 -and ($i -eq 0 -or $bytes[$i - 1] -ne 13)) {
                $lf++
            }
        }
        [pscustomobject]@{ Crlf = $crlf; Lf = $lf }
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:testRoot) {
        Remove-Item -LiteralPath $script:testRoot -Recurse -Force
    }
}

Describe 'ConvertTo-WtwUnixLineEndings' {
    It 'rewrites a CRLF zsh file to LF and leaves a LF bash file alone' {
        $dir = Join-Path $script:testRoot 'mix'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $zsh = Join-Path $dir 'wtw.zsh'
        $bash = Join-Path $dir 'wtw.bash'
        $cmd = Join-Path $dir 'wtw.cmd'
        [System.IO.File]::WriteAllText($zsh, "echo hi`r`n`r`nelif true`r`n")
        [System.IO.File]::WriteAllText($bash, "echo hi`n")
        [System.IO.File]::WriteAllText($cmd, "@echo off`r`n")

        InModuleScope wtw -Parameters @{ Dir = $dir } {
            ConvertTo-WtwUnixLineEndings -Path $Dir
        }

        $zshEol = Get-WtwEolCounts $zsh
        $bashEol = Get-WtwEolCounts $bash
        $cmdEol = Get-WtwEolCounts $cmd
        $zshEol.Crlf | Should -Be 0
        $zshEol.Lf | Should -Be 3
        $bashEol.Crlf | Should -Be 0
        $bashEol.Lf | Should -Be 1
        $cmdEol.Crlf | Should -Be 1
    }

    It 'accepts a single file path' {
        $zsh = Join-Path $script:testRoot 'one.zsh'
        [System.IO.File]::WriteAllText($zsh, "then`r`nelif`r`n")

        InModuleScope wtw -Parameters @{ File = $zsh } {
            ConvertTo-WtwUnixLineEndings -Path $File
        }

        $eol = Get-WtwEolCounts $zsh
        $eol.Crlf | Should -Be 0
        $eol.Lf | Should -Be 2
    }

    It 'is a no-op when the path does not exist' {
        $missing = Join-Path $script:testRoot 'missing-dir'
        InModuleScope wtw -Parameters @{ Missing = $missing } {
            { ConvertTo-WtwUnixLineEndings -Path $Missing } | Should -Not -Throw
        }
    }
}

Describe 'Test-WtwShellRcHasWrapper' {
    It 'matches the install comment' {
        InModuleScope wtw {
            Test-WtwShellRcHasWrapper -RcContent "# wtw — worktree + workspace manager`nsource ~/.wtw/shell/wtw.zsh" -WrapperFileName 'wtw.zsh' |
                Should -BeTrue
        }
    }

    It 'matches a chezmoi source without the install comment' {
        InModuleScope wtw {
            $rc = @'
if [ -f "$HOME/.wtw/shell/wtw.zsh" ]; then
  source "$HOME/.wtw/shell/wtw.zsh"
fi
'@
            Test-WtwShellRcHasWrapper -RcContent $rc -WrapperFileName 'wtw.zsh' | Should -BeTrue
        }
    }

    It 'does not match an unrelated rc' {
        InModuleScope wtw {
            Test-WtwShellRcHasWrapper -RcContent 'export EDITOR=vim' -WrapperFileName 'wtw.zsh' |
                Should -BeFalse
        }
    }
}

Describe 'shipped unix wrappers' {
    It 'pins *.zsh to LF in the module gitattributes' {
        $attrs = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../.gitattributes') -Raw
        $attrs | Should -Match '\*\.zsh\s+text\s+eol=lf'
    }

    It 'keeps repo wtw.zsh and wtw.bash as LF' {
        foreach ($name in @('wtw.zsh', 'wtw.bash')) {
            $eol = Get-WtwEolCounts (Join-Path $PSScriptRoot '../shell' $name)
            $eol.Crlf | Should -Be 0
            $eol.Lf | Should -BeGreaterThan 0
        }
    }
}
