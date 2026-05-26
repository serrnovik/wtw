BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'Restore-WtwInstalledModule' {
    It 're-imports the installed module when a session script loaded a repo-local module' {
        InModuleScope wtw {
            Mock Test-Path { $true }
            Mock Import-Module {}

            Restore-WtwInstalledModule

            Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter {
                $Name -eq (Join-Path $HOME '.wtw/module/wtw.psm1') -and $Global -and $Force -and $DisableNameChecking
            }
        }
    }

    It 'does nothing when repo-local module development is explicitly enabled' {
        InModuleScope wtw {
            $oldValue = $env:WTW_USE_REPO_MODULE
            try {
                $env:WTW_USE_REPO_MODULE = '1'
                Mock Test-Path { $true }
                Mock Import-Module {}

                Restore-WtwInstalledModule

                Should -Invoke Import-Module -Times 0 -Exactly
            } finally {
                $env:WTW_USE_REPO_MODULE = $oldValue
            }
        }
    }
}
