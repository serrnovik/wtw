BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    . "$PSScriptRoot/../private/New-WtwWorkspaceFile.ps1"
    . "$PSScriptRoot/../private/Read-JsoncFile.ps1"
    . "$PSScriptRoot/../private/ConvertTo-PeacockColorBlock.ps1"
    . "$PSScriptRoot/../private/Get-WtwRegistry.ps1"
}

Describe 'New-WtwWorkspaceFile' {
    BeforeAll {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "wtw-wsgen-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null

        # Create a minimal template
        $script:templatePath = Join-Path $script:tempDir 'template.code-workspace'
        $template = [PSCustomObject]@{
            folders = @(
                [PSCustomObject]@{ name = 'myrepo'; path = '/original/path' }
                [PSCustomObject]@{ path = '/stable/obsidian' }
            )
            settings = [PSCustomObject]@{
                'terminal.integrated.cwd' = '${workspaceFolder:myrepo}'
                'peacock.color'           = '#000000'
            }
        }
        $template | ConvertTo-Json -Depth 10 | Set-Content $script:templatePath

        # Fake registry so New-WtwWorkspaceFile can resolve mainPath leaf
        $script:origRegistry = $null
        if (Test-Path (Join-Path $HOME '.wtw' 'registry.json')) {
            $script:origRegistry = Get-Content (Join-Path $HOME '.wtw' 'registry.json') -Raw
        }
        $fakeRegistry = [PSCustomObject]@{
            repos = [PSCustomObject]@{
                testRepo = [PSCustomObject]@{
                    mainPath = '/original/myrepo'
                    aliases  = @('tr')
                    worktrees = [PSCustomObject]@{}
                }
            }
        }
        $fakeRegistry | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $HOME '.wtw' 'registry.json')
    }

    AfterAll {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        # Restore original registry
        if ($script:origRegistry) {
            $script:origRegistry | Set-Content (Join-Path $HOME '.wtw' 'registry.json')
        }
    }

    It 'generates workspace with replaced code folder' {
        $outPath = Join-Path $script:tempDir 'output.code-workspace'
        New-WtwWorkspaceFile `
            -RepoName 'testRepo' `
            -Name 'testRepo_auth' `
            -CodeFolderPath '/new/worktree/path' `
            -TemplatePath $script:templatePath `
            -OutputPath $outPath `
            -Color '#e05d44' `
            -Managed

        Test-Path $outPath | Should -BeTrue
        $ws = Get-Content $outPath -Raw | ConvertFrom-Json
        $ws.folders[0].path | Should -Be '/new/worktree/path'
        $ws.folders[0].name | Should -Be 'testRepo_auth'
    }

    It 'preserves stable folders from template' {
        $outPath = Join-Path $script:tempDir 'output2.code-workspace'
        New-WtwWorkspaceFile `
            -RepoName 'testRepo' `
            -Name 'testRepo_billing' `
            -CodeFolderPath '/new/path' `
            -TemplatePath $script:templatePath `
            -OutputPath $outPath `
            -Color '#2ba7d0'

        $ws = Get-Content $outPath -Raw | ConvertFrom-Json
        $ws.folders.Count | Should -Be 2
        $ws.folders[1].path | Should -Be '/stable/obsidian'
    }

    It 'replaces workspaceFolder references' {
        $outPath = Join-Path $script:tempDir 'output3.code-workspace'
        New-WtwWorkspaceFile `
            -RepoName 'testRepo' `
            -Name 'testRepo_feat' `
            -CodeFolderPath '/feat/path' `
            -TemplatePath $script:templatePath `
            -OutputPath $outPath `
            -Color '#97ca00'

        $ws = Get-Content $outPath -Raw | ConvertFrom-Json
        $ws.settings.'terminal.integrated.cwd' | Should -Be '${workspaceFolder:testRepo_feat}'
    }

    It 'injects Peacock color' {
        $outPath = Join-Path $script:tempDir 'output4.code-workspace'
        New-WtwWorkspaceFile `
            -RepoName 'testRepo' `
            -Name 'testRepo_color' `
            -CodeFolderPath '/path' `
            -TemplatePath $script:templatePath `
            -OutputPath $outPath `
            -Color '#b300b3' `
            -Managed

        $ws = Get-Content $outPath -Raw | ConvertFrom-Json
        $ws.settings.'peacock.color' | Should -Be '#b300b3'
        $ws.settings.'workbench.colorCustomizations'.'titleBar.activeBackground' | Should -Be '#b300b3'
    }

    It 'adds wtw metadata when -Managed' {
        $outPath = Join-Path $script:tempDir 'output5.code-workspace'
        New-WtwWorkspaceFile `
            -RepoName 'testRepo' `
            -Name 'testRepo_meta' `
            -CodeFolderPath '/path' `
            -TemplatePath $script:templatePath `
            -OutputPath $outPath `
            -Color '#44cc11' `
            -Branch 'feat/meta' `
            -WorktreePath '/path' `
            -Managed

        $ws = Get-Content $outPath -Raw | ConvertFrom-Json
        $ws.settings.'wtw.managed' | Should -BeTrue
        $ws.settings.'wtw.repo' | Should -Be 'testRepo'
        $ws.settings.'wtw.task' | Should -Be 'testRepo_meta'
        $ws.settings.'wtw.branch' | Should -Be 'feat/meta'
    }

    It 'omits wtw metadata when not -Managed' {
        $outPath = Join-Path $script:tempDir 'output6.code-workspace'
        New-WtwWorkspaceFile `
            -RepoName 'testRepo' `
            -Name 'standalone' `
            -CodeFolderPath '/path' `
            -TemplatePath $script:templatePath `
            -OutputPath $outPath `
            -Color '#dfb317'

        $ws = Get-Content $outPath -Raw | ConvertFrom-Json
        $ws.settings.'wtw.managed' | Should -BeNullOrEmpty
    }
}
