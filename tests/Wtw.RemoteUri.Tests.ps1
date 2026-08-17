BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'ConvertTo-WtwRemotePath' {
    # Each of these three transforms, done wrong, yields a URI VS Code accepts
    # and then opens as a blank window — no error to diagnose from.
    It 'flips backslashes, lower-cases the drive, and adds the leading slash' {
        ConvertTo-WtwRemotePath -Path 'C:\Users\dev\Data\repo_auth' -Platform 'windows' |
            Should -Be '/c:/Users/dev/Data/repo_auth'
    }

    It 'handles a bare drive root' {
        ConvertTo-WtwRemotePath -Path 'D:\' -Platform 'windows' | Should -Be '/d:/'
        ConvertTo-WtwRemotePath -Path 'D:'  -Platform 'windows' | Should -Be '/d:/'
    }

    It 'accepts a Windows path that already uses forward slashes' {
        ConvertTo-WtwRemotePath -Path 'C:/Users/dev/x' -Platform 'windows' | Should -Be '/c:/Users/dev/x'
    }

    It 'leaves UNC paths in their URI-shaped form' {
        ConvertTo-WtwRemotePath -Path '\\server\share\repo' -Platform 'windows' | Should -Be '//server/share/repo'
    }

    It 'passes POSIX paths through unchanged' {
        ConvertTo-WtwRemotePath -Path '/home/dev/data/repo' -Platform 'linux' | Should -Be '/home/dev/data/repo'
        ConvertTo-WtwRemotePath -Path '/Users/dev/Data/repo' -Platform 'macos' | Should -Be '/Users/dev/Data/repo'
    }

    It 'does not mangle a POSIX path that looks drive-ish on a POSIX host' {
        ConvertTo-WtwRemotePath -Path '/home/c:weird' -Platform 'linux' | Should -Be '/home/c:weird'
    }
}

Describe 'ConvertTo-WtwRemoteUri' {
    It 'builds the ssh-remote authority for a Windows worktree' {
        ConvertTo-WtwRemoteUri -Path 'C:\Users\dev\Data\snogit\repo_auth' -HostName 'workstation' -Platform 'windows' |
            Should -Be 'vscode-remote://ssh-remote+workstation/c:/Users/dev/Data/snogit/repo_auth'
    }

    It 'builds the ssh-remote authority for a POSIX worktree' {
        ConvertTo-WtwRemoteUri -Path '/home/dev/repo_auth' -HostName 'laptop' -Platform 'linux' |
            Should -Be 'vscode-remote://ssh-remote+laptop/home/dev/repo_auth'
    }

    It 'escapes spaces in path segments' {
        ConvertTo-WtwRemoteUri -Path '/home/dev/my repo' -HostName 'box' -Platform 'linux' |
            Should -Be 'vscode-remote://ssh-remote+box/home/dev/my%20repo'
    }

    It 'leaves the Windows drive colon unescaped' {
        # %3A here would stop VS Code mapping the segment back to a drive.
        $uri = ConvertTo-WtwRemoteUri -Path 'C:\a b\c' -HostName 'w' -Platform 'windows'
        $uri | Should -Be 'vscode-remote://ssh-remote+w/c:/a%20b/c'
        $uri | Should -Not -Match '%3A'
    }

    It 'escapes a workspace file name with spaces' {
        ConvertTo-WtwRemoteUri -Path 'C:\ws\snowmain - Auth Work.code-workspace' -HostName 'at' -Platform 'windows' |
            Should -Be 'vscode-remote://ssh-remote+at/c:/ws/snowmain%20-%20Auth%20Work.code-workspace'
    }
}
