BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Resolve-WtwEditorCommand' {
    It 'resolves "cursor" exactly' {
        Resolve-WtwEditorCommand 'cursor' | Should -Be 'cursor'
    }

    It 'resolves "cur" prefix to cursor' {
        Resolve-WtwEditorCommand 'cur' | Should -Be 'cursor'
    }

    It 'resolves "code" exactly' {
        Resolve-WtwEditorCommand 'code' | Should -Be 'code'
    }

    It 'resolves "co" prefix to code' {
        Resolve-WtwEditorCommand 'co' | Should -Be 'code'
    }

    It 'resolves "anti" prefix to antigravity' {
        Resolve-WtwEditorCommand 'anti' | Should -Be 'antigravity'
    }

    It 'resolves "antigravity" exactly' {
        Resolve-WtwEditorCommand 'antigravity' | Should -Be 'antigravity'
    }

    It 'resolves "sg" prefix to sourcegit' {
        Resolve-WtwEditorCommand 'sg' | Should -Be 'sourcegit'
    }

    It 'resolves "sgit" to sourcegit' {
        Resolve-WtwEditorCommand 'sgit' | Should -Be 'sourcegit'
    }

    It 'returns null for unknown editor' {
        Resolve-WtwEditorCommand 'vim' | Should -BeNullOrEmpty
    }

    It 'returns null for empty string' {
        Resolve-WtwEditorCommand '' | Should -BeNullOrEmpty
    }
}
