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

        It "exits 1 for a drive letter without a colon" {
            & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath -All -WhatIf -Drive 'C' 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
        }

        It "accepts a lowercase drive letter" {
            & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath -All -WhatIf -Drive 'c:' 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
        }

        It "accepts a drive with a trailing backslash" {
            & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath -All -WhatIf -Drive 'C:\' 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
        }
    }

    Context "-List mode" {

        It "exits 0 on a machine with no Autodesk products" {
            & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath -List 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
        }

        It "logs the -List result and exits before any removal step" {
            $log = Join-Path $env:TEMP "pester-adsk-list-$(New-Guid).log"
            try {
                & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath -List -LogPath $log 2>&1 | Out-Null
                Select-String -Path $log -Pattern '-List: displayed' | Should -Not -BeNullOrEmpty
                Select-String -Path $log -Pattern 'Uninstalling:' -SimpleMatch | Should -BeNullOrEmpty
            } finally {
                Remove-Item $log -ErrorAction SilentlyContinue
            }
        }
    }

    Context "-Products mode" {

        It "exits 0 and warns when no installed product matches" {
            & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath `
                -Products 'NoSuchProductXyz123' -WhatIf 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0
        }

        It "logs a warning for the unmatched product name" {
            $log = Join-Path $env:TEMP "pester-adsk-prod-$(New-Guid).log"
            try {
                & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath `
                    -Products 'NoSuchProductXyz123' -WhatIf -LogPath $log 2>&1 | Out-Null
                Select-String -Path $log -Pattern "No installed product matched 'NoSuchProductXyz123'" |
                    Should -Not -BeNullOrEmpty
            } finally {
                Remove-Item $log -ErrorAction SilentlyContinue
            }
        }
    }

    Context "-Install validation" {

        It "logs an error when the installer path does not exist" {
            $log = Join-Path $env:TEMP "pester-adsk-install-$(New-Guid).log"
            try {
                & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath `
                    -Install "$env:TEMP\pester-no-such-installer-$(New-Guid).exe" -LogPath $log 2>&1 | Out-Null
                Select-String -Path $log -Pattern 'Installer not found' | Should -Not -BeNullOrEmpty
            } finally {
                Remove-Item $log -ErrorAction SilentlyContinue
            }
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
