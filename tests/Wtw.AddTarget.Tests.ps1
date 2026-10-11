BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'Resolve-WtwAddTarget' {
    It 'treats a bare name inside a worktree as the task' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-add-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $root | Out-Null
        Set-Content -LiteralPath (Join-Path $root '.git') -Value 'gitdir: /tmp/main/.git/worktrees/demo'
        Push-Location $root
        try {
            $resolved = InModuleScope wtw { Resolve-WtwAddTarget -Path 'update-routine' -Task $null }
            $resolved.Task | Should -Be 'update-routine'
            $resolved.Path | Should -Be (Get-Location).Path
        } finally {
            Pop-Location
            Remove-Item $root -Recurse -Force
        }
    }

    It 'reports a missing directory and points at wtw create' {
        $out = InModuleScope wtw {
            Resolve-WtwAddTarget -Path 'missing-dir/update-routine' -Task $null 2>&1 | Out-String
        }
        $out | Should -Match 'does not exist'
        $out | Should -Match 'wtw create'
    }
}
