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
        $command = Resolve-WtwEditorCommand 'sg'

        $command.type | Should -Be 'macapp'
        $command.appName | Should -Be 'SourceGit'
        $command.winCmd | Should -Be 'SourceGit'
        $command.linuxCmd | Should -Be 'sourcegit'
        $command.macArgsViaCli | Should -Be $true
    }

    It 'resolves "sgit" to sourcegit' {
        $command = Resolve-WtwEditorCommand 'sgit'

        $command.type | Should -Be 'macapp'
        $command.appName | Should -Be 'SourceGit'
    }

    It 'resolves "codex" to Codex Desktop launcher metadata' {
        $command = Resolve-WtwEditorCommand 'codex'

        $command.type | Should -Be 'codex'
        $command.appName | Should -Be 'Codex'
        $command.cmd | Should -Be 'codex'
    }

    It 'resolves "cmux" and "cm" to cmux launcher metadata' {
        $command = Resolve-WtwEditorCommand 'cmux'
        $alias = Resolve-WtwEditorCommand 'cm'

        $command.type | Should -Be 'cmux'
        $command.appName | Should -Be 'cmux'
        $command.cmd | Should -Be 'cmux'
        $alias.type | Should -Be 'cmux'
    }

    It 'resolves "wmux" and "wm" to wmux launcher metadata' {
        $command = Resolve-WtwEditorCommand 'wmux'
        $alias = Resolve-WtwEditorCommand 'wm'

        $command.type | Should -Be 'wmux'
        $command.appName | Should -Be 'wmux'
        $command.cmd | Should -Be 'wmux'
        $alias.type | Should -Be 'wmux'
    }

    It 'returns null for unknown editor' {
        Resolve-WtwEditorCommand 'vim' | Should -BeNullOrEmpty
    }

    It 'returns null for empty string' {
        Resolve-WtwEditorCommand '' | Should -BeNullOrEmpty
    }
}
