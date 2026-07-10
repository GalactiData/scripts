BeforeAll {
    $script:ScriptPath = Resolve-Path "$PSScriptRoot/../../powershell/Get-PatchStatus/Get-PatchStatus.ps1"
}

Describe "Get-PatchStatus.ps1" {

    Context "Parameter validation" {

        It "rejects -WarnDays outside the valid range" {
            & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath -WarnDays 0 -SkipUpdateSearch 2>&1 | Out-Null
            $LASTEXITCODE | Should -Not -Be 0
        }

        It "exits 1 when -WarnDays is not lower than -CritDays" {
            & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath -WarnDays 90 -CritDays 30 -SkipUpdateSearch 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context "Report run (offline)" {

        BeforeAll {
            $script:Csv = Join-Path $env:TEMP "pester-patchstatus-$(New-Guid).csv"
            $script:Output = & powershell.exe -NonInteractive -NoProfile -File $script:ScriptPath `
                -SkipUpdateSearch -OutputPath $script:Csv 2>&1 | Out-String
            $script:ExitCode = $LASTEXITCODE
        }

        AfterAll {
            Remove-Item $script:Csv -ErrorAction SilentlyContinue
        }

        It "exits with a monitoring status code (0, 1, or 2)" {
            $script:ExitCode | Should -BeIn 0, 1, 2
        }

        It "reports the expected fields" {
            $script:Output | Should -Match 'Last update'
            $script:Output | Should -Match 'Reboot pending'
            $script:Output | Should -Match 'Status:'
        }

        It "exports a CSV with the expected columns" {
            Test-Path $script:Csv | Should -BeTrue
            $row = Import-Csv $script:Csv
            $row.Computer | Should -Be $env:COMPUTERNAME
            $row.PSObject.Properties.Name | Should -Contain 'RebootPending'
            $row.Status | Should -BeIn 'OK', 'WARNING', 'CRITICAL'
        }
    }
}
