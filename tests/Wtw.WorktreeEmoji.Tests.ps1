BeforeAll {
    Import-Module "$PSScriptRoot/../wtw.psm1" -Force -DisableNameChecking
}

Describe 'Get-WtwWorktreeEmojiPool' {
    It 'is unique single-scalar glyphs and excludes color circles' {
        InModuleScope wtw {
            $pool = @(Get-WtwWorktreeEmojiPool)
            $pool.Count | Should -BeGreaterThan 150
            $pool | Should -BeExactly ($pool | Select-Object -Unique)

            $circles = @(Get-WtwColorCircleCodepoints)
            foreach ($glyph in $pool) {
                $cp = [char]::ConvertToUtf32($glyph, 0)
                $len = if ($cp -gt 0xFFFF) { 2 } else { 1 }
                $glyph.Length | Should -Be $len
                $circles | Should -Not -Contain $cp
            }

            $hedgehog = [char]::ConvertFromUtf32(0x1F994)
            $pool | Should -Contain $hedgehog
        }
    }
}

Describe 'Get-WtwDerivedWorktreeEmoji' {
    It 'is deterministic for the same task name' {
        InModuleScope wtw {
            $a = Get-WtwDerivedWorktreeEmoji -Name 'feature'
            $b = Get-WtwDerivedWorktreeEmoji -Name 'feature'
            $a | Should -Not -BeNullOrEmpty
            $a | Should -Be $b
        }
    }

    It 'normalizes NFC before hashing' {
        InModuleScope wtw {
            $composed = [string]([char]0x00E9)          # é
            $decomposed = 'e' + [char]0x0301            # e + combining acute
            Get-WtwDerivedWorktreeEmoji -Name $composed |
                Should -Be (Get-WtwDerivedWorktreeEmoji -Name $decomposed)
        }
    }

    It 'is case-insensitive after branch-safe normalization' {
        InModuleScope wtw {
            Get-WtwDerivedWorktreeEmoji -Name 'Auth' |
                Should -Be (Get-WtwDerivedWorktreeEmoji -Name 'auth')
        }
    }
}

Describe 'Get-WtwWorktreeEmoji override' {
    It 'uses a stored override and treats none/auto as derived' {
        InModuleScope wtw {
            $derived = Get-WtwDerivedWorktreeEmoji -Name 'auth'
            $entry = [PSCustomObject]@{ prettyName = '🟠 auth'; emoji = '🦔' }
            Get-WtwWorktreeEmoji -WorktreeEntry $entry -TaskName 'auth' | Should -Be '🦔'

            Set-WtwWorktreeEmojiProperty -WorktreeEntry $entry -Emoji 'none' | Should -BeNullOrEmpty
            (Get-WtwPropertyNames -Object $entry) | Should -Not -Contain 'emoji'
            Get-WtwWorktreeEmoji -WorktreeEntry $entry -TaskName 'auth' | Should -Be $derived

            Set-WtwWorktreeEmojiProperty -WorktreeEntry $entry -Emoji 'auto' | Should -BeNullOrEmpty
            Get-WtwWorktreeEmoji -WorktreeEntry $entry -TaskName 'auth' | Should -Be $derived
        }
    }
}

Describe 'Format-WtwWorktreeDisplayName' {
    It 'composes repo + worktree glyphs with no space between them' {
        InModuleScope wtw {
            $glyph = Get-WtwDerivedWorktreeEmoji -Name 'auth'
            $repo = [PSCustomObject]@{ emoji = '🎸' }
            Format-WtwWorktreeDisplayName -Name '🟠 auth' -TaskName 'auth' -RepoEntry $repo |
                Should -Be "🎸${glyph} auth"
        }
    }

    It 'compacts whitespace in a multi-glyph repo prefix' {
        InModuleScope wtw {
            $glyph = Get-WtwDerivedWorktreeEmoji -Name 'auth'
            $repo = [PSCustomObject]@{ emoji = '🎭 ☸️' }
            Format-WtwWorktreeDisplayName -Name 'auth' -TaskName 'auth' -RepoEntry $repo |
                Should -Be "🎭☸️${glyph} auth"
        }
    }

    It 'omits the repo glyph when the repo has none' {
        InModuleScope wtw {
            $glyph = Get-WtwDerivedWorktreeEmoji -Name 'auth'
            Format-WtwWorktreeDisplayName -Name '🟠 auth' -TaskName 'auth' |
                Should -Be "$glyph auth"
        }
    }

    It 'strips color circles but keeps a custom leading pool emoji' {
        InModuleScope wtw {
            $glyph = Get-WtwDerivedWorktreeEmoji -Name 'pf037'
            $custom = [char]::ConvertFromUtf32(0x1F3C0) # 🏀
            if ($glyph -eq $custom) { $custom = [char]::ConvertFromUtf32(0x1F48E) } # 💎
            Format-WtwWorktreeDisplayName -Name "🟠 $custom PF037" -TaskName 'pf037' |
                Should -Be "$glyph $custom PF037"
        }
    }

    It 'does not stack when the name is already composed' {
        InModuleScope wtw {
            $glyph = Get-WtwDerivedWorktreeEmoji -Name 'auth'
            $composed = "🎸${glyph} auth"
            $repo = [PSCustomObject]@{ emoji = '🎸' }
            Format-WtwWorktreeDisplayName -Name $composed -TaskName 'auth' -RepoEntry $repo |
                Should -Be $composed
        }
    }

    It 'humanizes a derived task slug unless --name was custom' {
        InModuleScope wtw {
            Format-WtwWorktreeDisplayName -Name '🔴 NTB-real-dogfood' -TaskName 'NTB-real-dogfood' -WorktreeEmoji '🐕' |
                Should -Be '🐕 NTB real dogfood'

            $repo = [PSCustomObject]@{ emoji = '🎸' }
            Format-WtwWorktreeDisplayName `
                -Name '🎸🐕 NTB-real-dogfood' `
                -TaskName 'NTB-real-dogfood' `
                -WorktreeEmoji '🐕' `
                -RepoEntry $repo |
                Should -Be '🎸🐕 NTB real dogfood'

            Format-WtwWorktreeDisplayName -Name 'Login flow' -TaskName 'auth' -WorktreeEmoji '🐕' |
                Should -Be '🐕 Login flow'
            Format-WtwWorktreeDisplayName -Name 'Blue Feature' -TaskName 'feature' -WorktreeEmoji '🐕' |
                Should -Be '🐕 Blue Feature'
            Format-WtwWorktreeDisplayName `
                -Name 'hetzner1 cluster server 02' `
                -TaskName 'hetzner1-cluster-resilience-2026-09-refresh' `
                -WorktreeEmoji '🐕' |
                Should -Be '🐕 hetzner1 cluster server 02'
        }
    }
}

Describe 'ConvertTo-WtwHumanizedLabel' {
    It 'replaces dashes and underscores on slug-equivalent labels' {
        InModuleScope wtw {
            ConvertTo-WtwHumanizedLabel -Name 'NTB-real-dogfood' -Slug 'NTB-real-dogfood' |
                Should -Be 'NTB real dogfood'
            ConvertTo-WtwHumanizedLabel -Name 'ntb_live_dogfood_fixes' -Slug 'ntb_live_dogfood_fixes' |
                Should -Be 'ntb live dogfood fixes'
            ConvertTo-WtwHumanizedLabel -Name 'Login flow' -Slug 'auth' |
                Should -Be 'Login flow'
            ConvertTo-WtwHumanizedLabel -Name 'keep-dashes' -Specified |
                Should -Be 'keep-dashes'
        }
    }
}

Describe 'Get-WtwNameWithoutColorCircle' {
    It 'strips only leading color circles' {
        InModuleScope wtw {
            Get-WtwNameWithoutColorCircle -Name '🟠 auth' | Should -Be 'auth'
            Get-WtwNameWithoutColorCircle -Name '🏀 PF037' | Should -Be '🏀 PF037'
        }
    }
}

Describe 'Format-WtwDetailedList emoji field' {
    It 'prints Emoji separately and keeps Name/Task unmerged' {
        InModuleScope wtw {
            $items = @(
                [PSCustomObject]@{
                    Kind         = 'repo'
                    Repo         = '🎸 snowmain1'
                    RepoName     = 'snowmain1'
                    Emoji        = '🎸'
                    Task         = '-'
                    TaskName     = '-'
                    Aliases      = "sn1`nsnowmain1"
                    Branch       = 'main'
                    Color        = '#aaaaaa'
                    Path         = '/tmp/snowmain1'
                    Workspace    = 'snowmain1.code-workspace'
                    AgentProfile = 'solo'
                }
                [PSCustomObject]@{
                    Kind         = 'wt'
                    Repo         = '🎸 snowmain1'
                    RepoName     = 'snowmain1'
                    Emoji        = '🐕'
                    Task         = '🐕 ntb_live_dogfood_fixes'
                    TaskName     = 'ntb_live_dogfood_fixes'
                    PrettyName   = '🟢 ntb_live_dogfood_fixes'
                    Aliases      = 'sn1-ntb_live_dogfood_fixes'
                    Branch       = 'fix/ntb-live-dogfood'
                    Color        = '#dd2cdd'
                    Path         = '/tmp/snowmain1_ntb_live_dogfood_fixes'
                    Workspace    = '🎸🐕 ntb_live_dogfood_fixes.code-workspace'
                    Created      = '2026-08-31'
                    AgentProfile = 'solo'
                    SupersetId   = $null
                }
            )
            $output = Format-WtwDetailedList $items *>&1 | Out-String
            $output | Should -Match 'Emoji     : 🎸'
            $output | Should -Match 'Emoji     : 🐕'
            $output | Should -Match 'Name      : 🟢 ntb_live_dogfood_fixes'
            $output | Should -Match 'Task      : ntb_live_dogfood_fixes'
            $output | Should -Not -Match 'Name      : 🎸🐕'
            $output | Should -Not -Match 'Task      : 🐕 ntb_live_dogfood_fixes'
        }
    }
}
