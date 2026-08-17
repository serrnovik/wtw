BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'Get-WtwEditorFamily' {
    It 'gives every member the fields all four call sites project from' {
        foreach ($member in Get-WtwEditorFamily) {
            $member.Id           | Should -Not -BeNullOrEmpty
            $member.Name         | Should -Not -BeNullOrEmpty
            @($member.Prefixes).Count     | Should -BeGreaterThan 0
            @($member.Cli).Count          | Should -BeGreaterThan 0
            @($member.RemoteExts).Count   | Should -BeGreaterThan 0
            @($member.SettingsDirs).Count | Should -BeGreaterThan 0
        }
    }

    It 'uses the canonical id as its own first CLI candidate or a documented rename' {
        foreach ($member in Get-WtwEditorFamily) {
            # Antigravity is the one member whose CLI was renamed away from its id.
            if ($member.Id -eq 'antigravity') {
                $member.Cli[0] | Should -Be 'antigravity-ide'
                $member.Cli    | Should -Contain 'antigravity'
            } else {
                $member.Cli | Should -Contain $member.Id
            }
        }
    }

    It 'keeps Cursor first so short prefixes resolve the way they always have' {
        (Get-WtwEditorFamily)[0].Id | Should -Be 'cursor'
    }

    It 'gives VSCodium a non-Microsoft Remote-SSH extension' {
        # Microsoft's Remote-SSH is proprietary and absent from Open VSX, so a
        # shared constant here would produce an uninstallable extension id.
        $codium = Get-WtwEditorFamilyMember -Id 'codium'
        $codium.RemoteExts | Should -Not -Contain 'ms-vscode-remote.remote-ssh'
    }

    It 'resolves shortcuts to members by prefix' {
        (Resolve-WtwEditorFamilyMember -Name 'cur').Id  | Should -Be 'cursor'
        (Resolve-WtwEditorFamilyMember -Name 'co').Id   | Should -Be 'code'
        (Resolve-WtwEditorFamilyMember -Name 'anti').Id | Should -Be 'antigravity'
    }

    It 'returns null for non-family editors' {
        Resolve-WtwEditorFamilyMember -Name 't3'    | Should -BeNullOrEmpty
        Resolve-WtwEditorFamilyMember -Name 'cmux'  | Should -BeNullOrEmpty
        Resolve-WtwEditorFamilyMember -Name 'droid' | Should -BeNullOrEmpty
    }
}

Describe 'Get-WtwEditorMacCliHints' {
    It 'pairs Antigravity bundles with their matching CLI by index' {
        $hints = Get-WtwEditorMacCliHints -Member (Get-WtwEditorFamilyMember -Id 'antigravity')

        $ide = $hints | Where-Object { $_.App -eq '/Applications/Antigravity IDE.app' }
        $ide.Name | Should -Be 'antigravity-ide'
        $ide.Bin  | Should -Be '/Applications/Antigravity IDE.app/Contents/Resources/app/bin/antigravity-ide'

        $legacy = $hints | Where-Object { $_.App -eq '/Applications/Antigravity.app' }
        $legacy.Name | Should -Be 'antigravity'
    }

    It 'stays one hint per bundle when stored in a hashtable' {
        # Regression: the caller wrapped this in @(), nesting the array. Filtering
        # then matched the single inner array, and `$hit.App` interpolated every
        # path at once — "installed at /Applications/Antigravity IDE.app
        # /Applications/Antigravity.app, but 'antigravity-ide antigravity' is not
        # on PATH".
        $map = @{}
        $map['Antigravity'] = Get-WtwEditorMacCliHints -Member (Get-WtwEditorFamilyMember -Id 'antigravity')

        $map['Antigravity'].Count | Should -Be 2
        foreach ($hint in $map['Antigravity']) {
            $hint.App  | Should -BeOfType [string]
            $hint.Name | Should -BeOfType [string]
            $hint.App  | Should -Not -Match ' /Applications/'
        }

        $first = $map['Antigravity'] | Select-Object -First 1
        $first.App  | Should -Be '/Applications/Antigravity IDE.app'
        $first.Name | Should -Be 'antigravity-ide'
    }

    It 'derives the VS Code hint that used to be hand-written' {
        $hints = Get-WtwEditorMacCliHints -Member (Get-WtwEditorFamilyMember -Id 'code')
        $hints[0].App  | Should -Be '/Applications/Visual Studio Code.app'
        $hints[0].Bin  | Should -Be '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code'
        $hints[0].Name | Should -Be 'code'
    }
}

Describe 'Resolve-WtwEditorCommand stays projected from the family table' {
    It 'still resolves every family prefix to its canonical id' {
        foreach ($member in Get-WtwEditorFamily) {
            foreach ($prefix in $member.Prefixes) {
                Resolve-WtwEditorCommand $prefix | Should -Be $member.Id
            }
        }
    }
}

Describe 'Resolve-WtwFuzzyMatch with no candidate in range' {
    It 'returns a clean no-match without writing to the error stream' {
        # Sort-Object on an empty array yields $null, and `.Count` on $null throws
        # under strict mode. The old "returns null for unknown editor" assertion
        # passed anyway, because the errors went to the error stream while the
        # function returned nothing.
        $errors = @()
        $result = Resolve-WtwFuzzyMatch -Name 'zzzz' -Candidates @('cursor', 'code') -ErrorVariable errors -ErrorAction SilentlyContinue

        $errors.Count | Should -Be 0
        $result.Match | Should -BeNullOrEmpty
    }

    It 'lets an unknown editor name resolve quietly' {
        $errors = @()
        Resolve-WtwEditorCommand 'nonexistent-editor' -ErrorVariable errors -ErrorAction SilentlyContinue | Out-Null
        $errors.Count | Should -Be 0
    }
}

Describe 'Resolve-WtwEditorPreference' {
    It 'returns a single configured editor unchanged' {
        Mock Get-WtwEditorCliName { 'cursor' }
        Resolve-WtwEditorPreference -Editor 'cursor' | Should -Be 'cursor'
    }

    It 'picks the first runnable editor from a chain' {
        Mock Get-WtwEditorCliName { if ($Cmd -eq 'code') { 'code' } else { $null } }
        Resolve-WtwEditorPreference -Editor @('cursor', 'code') | Should -Be 'code'
    }

    It 'falls back to the last entry so the launcher emits its own diagnostic' {
        Mock Get-WtwEditorCliName { $null }
        Resolve-WtwEditorPreference -Editor @('cursor', 'code') | Should -Be 'code'
    }

    It 'honours a Require predicate, e.g. "has Remote-SSH"' {
        Mock Get-WtwEditorCliName { $Cmd }
        $result = Resolve-WtwEditorPreference -Editor @('cursor', 'code') -Require { param($n) $n -eq 'code' }
        $result | Should -Be 'code'
    }

    It 'passes an already-resolved descriptor straight through' {
        $descriptor = @{ type = 'cmux'; appName = 'cmux' }
        (Resolve-WtwEditorPreference -Editor $descriptor).type | Should -Be 'cmux'
    }

    It 'does not probe a CLI for non-family editors' {
        # t3/cmux have no CLI on PATH; their own launchers own the install check,
        # so requiring runnability here would make them unselectable.
        Mock Get-WtwEditorCliName { $null }
        (Resolve-WtwEditorPreference -Editor @('t3')).type | Should -Be 't3'
    }
}
