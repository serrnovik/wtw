BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'cmux machine/project group names' {
    It 'joins the machine badge and repo pretty name with a slash' {
        Format-WtwCmuxGroupName -MachineBadge '🍏SP' -ProjectName '🎸 snowmain1' |
            Should -Be '🍏SP/🎸 snowmain1'
        Format-WtwCmuxGroupName -MachineBadge '🧊AT' -ProjectName '🎭 kulissa-landing' |
            Should -Be '🧊AT/🎭 kulissa-landing'
        Format-WtwCmuxGroupName -MachineBadge '🧊AT' -ProjectName '' |
            Should -Be '🧊AT'
    }

    It 'keys groups by self/host plus repo, not the worktree name' {
        ConvertTo-WtwCmuxGroupKey -MachineId 'self' -RepoId 'snowmain1' |
            Should -Be 'wtw.group.self.snowmain1'
        ConvertTo-WtwCmuxGroupKey -MachineId 'Arctic Troll' -RepoId 'kulissa-landing' |
            Should -Be 'wtw.group.arctic-troll.kulissa-landing'
        ConvertTo-WtwCmuxGroupKey -MachineId 'arctictroll' -RepoId '' |
            Should -Be 'wtw.group.arctictroll'
    }

    It 'strips the host title separator from the machine badge' {
        $hostEntry = @{
            Name      = 'arctictroll'
            Aliases   = @('at')
            Emoji     = '🧊'
            Label     = 'AT'
            Separator = ' '
        }
        Get-WtwMachineBadge -HostEntry $hostEntry | Should -Be '🧊AT'
        Get-WtwHostTitlePrefix -HostEntry $hostEntry | Should -Be '🧊AT '
    }

    It 'builds a local spec from this machine plus the repo emoji' {
        Mock Get-WtwSelfBadge { '🍏SP' }

        $spec = Get-WtwCmuxLocalWorkspaceGroupSpec -Target ([PSCustomObject]@{
                RepoName      = 'snowmain1'
                TaskName      = 'auth'
                WorktreeEntry = [PSCustomObject]@{ path = $TestDrive }
                RepoEntry     = [PSCustomObject]@{
                    mainPath = $TestDrive
                    emoji    = '🎸'
                }
            })

        $spec.Name | Should -Be '🍏SP/🎸 snowmain1'
        $spec.Key | Should -Be 'wtw.group.self.snowmain1'
        $spec.Cwd | Should -Be ([System.IO.Path]::GetFullPath($TestDrive))
    }

    It 'builds a remote spec from the host badge plus the remote repo' {
        $hostEntry = @{
            Name      = 'arctictroll'
            Aliases   = @('at')
            Emoji     = '🧊'
            Label     = 'AT'
            Separator = ' '
        }
        $session = [PSCustomObject]@{
            RepoName  = 'kulissa-landing'
            RepoEmoji = '🎭'
        }

        $spec = Get-WtwCmuxRemoteWorkspaceGroupSpec -HostEntry $hostEntry -Session $session
        $spec.Name | Should -Be '🧊AT/🎭 kulissa-landing'
        $spec.Key | Should -Be 'wtw.group.arctictroll.kulissa-landing'
    }

    It 'fills a missing remote repo emoji from the local registry' {
        Mock Get-WtwRegistry {
            [PSCustomObject]@{
                repos = [PSCustomObject]@{
                    'kulissa-landing' = [PSCustomObject]@{ emoji = '🎭' }
                }
            }
        }

        $spec = Get-WtwCmuxRemoteWorkspaceGroupSpec `
            -HostEntry @{ Name = 'arctictroll'; Emoji = '🧊'; Label = 'AT'; Separator = ' ' } `
            -Session ([PSCustomObject]@{ RepoName = 'kulissa-landing'; RepoEmoji = $null })
        $spec.Name | Should -Be '🧊AT/🎭 kulissa-landing'
    }

    It 'uses only the host badge when a remote home session has no repo' {
        $hostEntry = @{ Name = 'arctictroll'; Emoji = '🧊'; Label = 'AT'; Separator = '.' }
        $spec = Get-WtwCmuxRemoteWorkspaceGroupSpec `
            -HostEntry $hostEntry `
            -Session ([PSCustomObject]@{ RepoName = ''; RepoEmoji = $null })
        $spec.Name | Should -Be '🧊AT'
        $spec.Key | Should -Be 'wtw.group.arctictroll'
    }
}

Describe 'Ensure-WtwCmuxWorkspaceGroup' {
    It 'creates a generated-header group when the key is new' {
        InModuleScope wtw {
            Mock Invoke-WtwCmuxCommand {
                $command = $ArgumentList -join ' '
                if ($command -eq 'workspace-group list --json') {
                    return [PSCustomObject]@{ ExitCode = 0; Output = '{ "groups": [] }' }
                }
                if ($ArgumentList[0] -eq 'workspace-group' -and $ArgumentList[1] -eq 'create') {
                    $ArgumentList | Should -Contain '--idempotency-key'
                    $ArgumentList | Should -Contain 'wtw.group.self.snowmain1'
                    $ArgumentList | Should -Not -Contain '--from'
                    return [PSCustomObject]@{
                        ExitCode = 0
                        Output   = @'
{
  "created": true,
  "group": {
    "ref": "workspace_group:3",
    "name": "🍏SP/🎸 snowmain1",
    "idempotency_key": "wtw.group.self.snowmain1",
    "member_workspace_refs": ["workspace:9"]
  }
}
'@
                    }
                }
                throw "unexpected cmux $($ArgumentList -join ' ')"
            }

            $group = Ensure-WtwCmuxWorkspaceGroup -Spec ([PSCustomObject]@{
                    Name = '🍏SP/🎸 snowmain1'
                    Key  = 'wtw.group.self.snowmain1'
                    Cwd  = $TestDrive
                })

            $group.Ref | Should -Be 'workspace_group:3'
            $group.Name | Should -Be '🍏SP/🎸 snowmain1'
        }
    }

    It 'reuses and renames an existing group with the same key' {
        InModuleScope wtw {
            $script:renamed = $false
            Mock Invoke-WtwCmuxCommand {
                $command = $ArgumentList -join ' '
                if ($command -eq 'workspace-group list --json') {
                    return [PSCustomObject]@{
                        ExitCode = 0
                        Output   = @'
{
  "groups": [
    {
      "ref": "workspace_group:1",
      "name": "🍏MA/🎸 snowmain1",
      "idempotency_key": "wtw.group.self.snowmain1",
      "member_workspace_refs": ["workspace:1"]
    }
  ]
}
'@
                    }
                }
                if ($ArgumentList[0] -eq 'workspace-group' -and $ArgumentList[1] -eq 'rename') {
                    $script:renamed = $true
                    $ArgumentList | Should -Contain 'workspace_group:1'
                    $ArgumentList | Should -Contain '🍏SP/🎸 snowmain1'
                    return [PSCustomObject]@{ ExitCode = 0; Output = '' }
                }
                throw "unexpected cmux $($ArgumentList -join ' ')"
            }

            $group = Ensure-WtwCmuxWorkspaceGroup -Spec ([PSCustomObject]@{
                    Name = '🍏SP/🎸 snowmain1'
                    Key  = 'wtw.group.self.snowmain1'
                    Cwd  = $TestDrive
                })

            $group.Ref | Should -Be 'workspace_group:1'
            $group.Name | Should -Be '🍏SP/🎸 snowmain1'
            $script:renamed | Should -BeTrue
        }
    }
}

Describe 'wtw cmux places the tab in the machine/project group' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-cmux-group-" + [guid]::NewGuid())
        $script:projectPath = Join-Path $script:tempDir 'snowmain1'
        New-Item -ItemType Directory -Path $script:projectPath -Force | Out-Null
        $script:cmuxCalls = [System.Collections.Generic.List[string]]::new()
    }

    AfterEach {
        Remove-Item -Recurse -Force $script:tempDir -ErrorAction SilentlyContinue
    }

    It 'passes --group on new-workspace' {
        Mock Get-WtwSelfBadge { '🍏SP' } -ModuleName wtw
        Mock Test-WtwCmuxPresent { $true } -ModuleName wtw
        Mock Register-WtwCmuxProject { 'wtw.local' } -ModuleName wtw
        Mock Invoke-WtwCmuxCommand {
            $script:cmuxCalls.Add(($ArgumentList -join ' '))
            $command = $ArgumentList -join ' '
            if ($command -eq 'workspace-group list --json') {
                return [PSCustomObject]@{ ExitCode = 0; Output = '{ "groups": [] }' }
            }
            if ($ArgumentList[0] -eq 'workspace-group' -and $ArgumentList[1] -eq 'create') {
                return [PSCustomObject]@{
                    ExitCode = 0
                    Output   = '{"created":true,"group":{"ref":"workspace_group:4","name":"🍏SP/🎸 snowmain1","idempotency_key":"wtw.group.self.snowmain1"}}'
                }
            }
            if ($command -eq 'list-workspaces --json') {
                return [PSCustomObject]@{ ExitCode = 0; Output = '{ "workspaces": [] }' }
            }
            if ($command -eq 'current-workspace') {
                return [PSCustomObject]@{ ExitCode = 0; Output = 'workspace:11' }
            }
            return [PSCustomObject]@{ ExitCode = 0; Output = '' }
        } -ModuleName wtw

        Open-WtwCmuxWorkspace -Target ([PSCustomObject]@{
                RepoName      = 'snowmain1'
                TaskName      = $null
                WorktreeEntry = $null
                RepoEntry     = [PSCustomObject]@{
                    mainPath = $script:projectPath
                    emoji    = '🎸'
                }
            })

        $create = $script:cmuxCalls | Where-Object { $_ -like 'new-workspace *' } | Select-Object -First 1
        $create | Should -Match '--group workspace_group:4'
        $script:cmuxCalls | Should -Contain 'workspace-group add --group workspace_group:4 --workspace workspace:11'
    }

    It 'adds an already-open workspace to the group' {
        Mock Get-WtwSelfBadge { '🍏SP' } -ModuleName wtw
        Mock Test-WtwCmuxPresent { $true } -ModuleName wtw
        Mock Register-WtwCmuxProject { 'wtw.local' } -ModuleName wtw
        Mock Invoke-WtwCmuxCommand {
            $script:cmuxCalls.Add(($ArgumentList -join ' '))
            $command = $ArgumentList -join ' '
            if ($command -eq 'workspace-group list --json') {
                return [PSCustomObject]@{
                    ExitCode = 0
                    Output   = '{"groups":[{"ref":"workspace_group:4","name":"🍏SP/🎸 snowmain1","idempotency_key":"wtw.group.self.snowmain1","member_workspace_refs":[]}]}'
                }
            }
            if ($command -eq 'list-workspaces --json') {
                $cwd = $script:projectPath.Replace('\', '\\')
                return [PSCustomObject]@{
                    ExitCode = 0
                    Output   = @"
{ "workspaces": [ { "ref": "workspace:2", "title": "🎸 snowmain1", "current_directory": "$cwd" } ] }
"@
                }
            }
            return [PSCustomObject]@{ ExitCode = 0; Output = '' }
        } -ModuleName wtw

        Open-WtwCmuxWorkspace -Target ([PSCustomObject]@{
                RepoName      = 'snowmain1'
                TaskName      = $null
                WorktreeEntry = $null
                RepoEntry     = [PSCustomObject]@{
                    mainPath = $script:projectPath
                    emoji    = '🎸'
                }
            })

        $script:cmuxCalls | Should -Contain 'select-workspace --workspace workspace:2'
        $script:cmuxCalls | Should -Contain 'workspace-group add --group workspace_group:4 --workspace workspace:2'
        @($script:cmuxCalls | Where-Object { $_ -like 'new-workspace*' }).Count | Should -Be 0
    }
}

Describe 'Get-WtwSelfIdentity' {
    It 'writes emoji and label into config.self' {
        InModuleScope wtw {
            $script:saved = $null
            Mock Get-WtwConfig {
                [PSCustomObject]@{ editor = 'cursor'; hosts = [PSCustomObject]@{} }
            }
            Mock Save-WtwConfig {
                $script:saved = $Config
            }

            $identity = Set-WtwSelfIdentity -Emoji '🍏' -Label 'SP'
            $identity.Badge | Should -Be '🍏SP'
            $script:saved.self.emoji | Should -Be '🍏'
            $script:saved.self.label | Should -Be 'SP'
        }
    }
}
