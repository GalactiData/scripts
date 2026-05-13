BeforeAll {
    $script:ScriptPath = Resolve-Path "$PSScriptRoot/../../powershell/Remove-AutodeskAEC/Remove-AutodeskAEC.ps1"
}

Describe "Remove-AutodeskAEC.ps1" {

    Context "Parameter validation" {

        It "exits 1 when no action parameter is provided" {
            & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
        }

        It "exits 1 for an invalid drive letter" {
            & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath -All -WhatIf -Drive 'notadrive' 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
        }

        It "exits 1 for a UNC path" {
            & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath -All -WhatIf -Drive '\\server\share' 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context "-List mode" {

        It "exits 0 on a machine with no Autodesk products" {
            & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath -List 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
        }
    }

    Context "-WhatIf mode" {

        BeforeAll {
            $script:WhatIfLog = Join-Path $env:TEMP "pester-adsk-$(New-Guid).log"
            & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath `
                -All -WhatIf -LogPath $script:WhatIfLog 2>&1 | Out-Null
            $script:WhatIfExit = $LASTEXITCODE
        }

        AfterAll {
            Remove-Item $script:WhatIfLog -ErrorAction SilentlyContinue
        }

        It "exits 0" {
            $script:WhatIfExit | Should -Be 0
        }

        It "creates a log file" {
            Test-Path $script:WhatIfLog | Should -BeTrue
        }

        It "log contains 'Script started'" {
            Select-String -Path $script:WhatIfLog -Pattern 'Script started' |
                Should -Not -BeNullOrEmpty
        }

        It "log contains 'Discovery complete'" {
            Select-String -Path $script:WhatIfLog -Pattern 'Discovery complete' |
                Should -Not -BeNullOrEmpty
        }
    }
}
