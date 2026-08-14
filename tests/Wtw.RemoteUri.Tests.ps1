BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
    Get-ChildItem -Path "$PSScriptRoot/../private" -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
}

Describe 'ConvertTo-WtwRemotePath' {
    # Each of these three transforms, done wrong, yields a URI VS Code accepts
    # and then opens as a blank window — no error to diagnose from.
    It 'flips backslashes, lower-cases the drive, and adds the leading slash' {
        ConvertTo-WtwRemotePath -Path 'C:\Users\sno\Data\repo_auth' -Platform 'windows' |
            Should -Be '/c:/Users/sno/Data/repo_auth'
    }

    It 'handles a bare drive root' {
        ConvertTo-WtwRemotePath -Path 'D:\' -Platform 'windows' | Should -Be '/d:/'
        ConvertTo-WtwRemotePath -Path 'D:'  -Platform 'windows' | Should -Be '/d:/'
    }

    It 'accepts a Windows path that already uses forward slashes' {
        ConvertTo-WtwRemotePath -Path 'C:/Users/sno/x' -Platform 'windows' | Should -Be '/c:/Users/sno/x'
    }

    It 'leaves UNC paths in their URI-shaped form' {
        ConvertTo-WtwRemotePath -Path '\\server\share\repo' -Platform 'windows' | Should -Be '//server/share/repo'
    }

    It 'passes POSIX paths through unchanged' {
        ConvertTo-WtwRemotePath -Path '/home/sno/data/repo' -Platform 'linux' | Should -Be '/home/sno/data/repo'
        ConvertTo-WtwRemotePath -Path '/Users/sno/Data/repo' -Platform 'macos' | Should -Be '/Users/sno/Data/repo'
    }

    It 'does not mangle a POSIX path that looks drive-ish on a POSIX host' {
        ConvertTo-WtwRemotePath -Path '/home/c:weird' -Platform 'linux' | Should -Be '/home/c:weird'
    }
}

Describe 'ConvertTo-WtwRemoteUri' {
    It 'builds the ssh-remote authority for a Windows worktree' {
        ConvertTo-WtwRemoteUri -Path 'C:\Users\sno\Data\snogit\repo_auth' -HostName 'arctictroll' -Platform 'windows' |
            Should -Be 'vscode-remote://ssh-remote+arctictroll/c:/Users/sno/Data/snogit/repo_auth'
    }

    It 'builds the ssh-remote authority for a POSIX worktree' {
        ConvertTo-WtwRemoteUri -Path '/home/sno/repo_auth' -HostName 'snowpomme' -Platform 'linux' |
            Should -Be 'vscode-remote://ssh-remote+snowpomme/home/sno/repo_auth'
    }

    It 'escapes spaces in path segments' {
        ConvertTo-WtwRemoteUri -Path '/home/sno/my repo' -HostName 'box' -Platform 'linux' |
            Should -Be 'vscode-remote://ssh-remote+box/home/sno/my%20repo'
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
