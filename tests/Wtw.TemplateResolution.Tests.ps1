BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'workspace template resolution' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "wtw-tpl-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'finds a repo-shipped template by exact repo directory name' {
        $repoRoot = Join-Path $script:tempDir 'myrepo'
        $templateDir = Join-Path $repoRoot 'configs/workspace-templates'
        New-Item -Path $templateDir -ItemType Directory -Force | Out-Null
        $templatePath = Join-Path $templateDir 'myrepo.code-workspace.template'
        Set-Content -Path $templatePath -Value '{}'

        Resolve-WtwRepoTemplatePath -RepoRoot $repoRoot | Should -Be $templatePath
    }

    It 'finds the snowmain template for numbered snowmain worktrees' {
        $repoRoot = Join-Path $script:tempDir 'snowmain1'
        $templateDir = Join-Path $repoRoot 'configs/workspace-templates'
        New-Item -Path $templateDir -ItemType Directory -Force | Out-Null
        $templatePath = Join-Path $templateDir 'snowmain.code-workspace.template'
        Set-Content -Path $templatePath -Value '{}'

        Resolve-WtwRepoTemplatePath -RepoRoot $repoRoot | Should -Be $templatePath
    }

    It 'uses the only repo-shipped template when there is no name match' {
        $repoRoot = Join-Path $script:tempDir 'project'
        $templateDir = Join-Path $repoRoot 'configs/workspace-templates'
        New-Item -Path $templateDir -ItemType Directory -Force | Out-Null
        $templatePath = Join-Path $templateDir 'shared.code-workspace.template'
        Set-Content -Path $templatePath -Value '{}'

        Resolve-WtwRepoTemplatePath -RepoRoot $repoRoot | Should -Be $templatePath
    }

    It 'ships a minimal fallback template with the module' {
        $templatePath = Resolve-WtwDefaultTemplatePath

        Test-Path $templatePath | Should -BeTrue
        Get-Content -Path $templatePath -Raw | Should -Match '\{\{WTW_WORKSPACE_NAME\}\}'
        Get-Content -Path $templatePath -Raw | Should -Match '\{\{WTW_CODE_FOLDER\}\}'
    }
}
