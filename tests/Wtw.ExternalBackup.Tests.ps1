BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'Backup-WtwExternalConfig' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wtw-extbak-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
        $script:sourcePath = Join-Path $script:tempDir 'preference.json'
        Set-Content -Path $script:sourcePath -Value '{"ok":true}' -Encoding utf8
    }

    AfterEach {
        InModuleScope wtw {
            $script:WtwBackupRoot = $null
        }
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns null when the source file is missing' {
        InModuleScope wtw {
            Backup-WtwExternalConfig -Tool 'sourcegit' -Path '/tmp/wtw-missing-preference.json' |
                Should -BeNullOrEmpty
        }
    }

    It 'copies into ~/.wtw/backups/<system>/ and keeps only the last 3 plus age slots' {
        InModuleScope wtw -Parameters @{ TempDir = $script:tempDir; SourcePath = $script:sourcePath } {
            $script:WtwBackupRoot = Join-Path $TempDir 'backups'
            $now = Get-Date
            $dest = Backup-WtwExternalConfig -Tool 'sourcegit' -Path $SourcePath
            $dest | Should -Match 'preference\.json\.\d{8}-\d{6}-\d{3}\.bak$'
            Test-Path -LiteralPath $dest | Should -BeTrue

            $dir = Join-Path $script:WtwBackupRoot 'sourcegit'
            $stamp = 1
            foreach ($ageDays in 0.1, 0.2, 1, 2, 4, 8, 15, 40) {
                $extra = Join-Path $dir ("preference.json.{0:D3}.bak" -f $stamp)
                $stamp++
                Copy-Item -LiteralPath $SourcePath -Destination $extra
                (Get-Item -LiteralPath $extra).LastWriteTime = $now.AddDays(-$ageDays)
            }

            Clear-WtwExternalConfigBackups -Directory $dir -LeafPrefix 'preference.json'
            $kept = @(Get-ChildItem -LiteralPath $dir -File | Sort-Object LastWriteTime -Descending)
            $kept.Count | Should -BeLessOrEqual 6
            $kept.Count | Should -BeGreaterOrEqual 4

            $newestThree = @($kept | Select-Object -First 3)
            $newestThree.Count | Should -Be 3

            $ages = @($kept | ForEach-Object { ($now - $_.LastWriteTime).TotalDays })
            ($ages | Where-Object { $_ -ge 3 } | Measure-Object).Count | Should -BeGreaterOrEqual 1
            ($ages | Where-Object { $_ -ge 7 } | Measure-Object).Count | Should -BeGreaterOrEqual 1
            ($ages | Where-Object { $_ -ge 30 } | Measure-Object).Count | Should -BeGreaterOrEqual 1
        }
    }
}
