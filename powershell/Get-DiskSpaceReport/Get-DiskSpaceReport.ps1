#Requires -Version 5.1

<#
.SYNOPSIS
    Reports disk usage across local drives with configurable warning and critical thresholds.

.DESCRIPTION
    Checks all fixed local drives (or a specified subset) and displays free space with
    color-coded status: green for healthy, yellow for warning, red for critical.
    Optionally exports results to CSV.

.PARAMETER WarnPercent
    Flag drives with free space below this percentage. Default: 20.

.PARAMETER CriticalPercent
    Flag drives with free space below this percentage as critical. Default: 10.

.PARAMETER Drive
    One or more drive letters to check (e.g. C:, D:). Checks all fixed drives if omitted.

.PARAMETER OutputPath
    Path to export results as a CSV file.

.EXAMPLE
    .\Get-DiskSpaceReport.ps1

.EXAMPLE
    .\Get-DiskSpaceReport.ps1 -WarnPercent 25 -CriticalPercent 15

.EXAMPLE
    .\Get-DiskSpaceReport.ps1 -Drive C:, D: -OutputPath "C:\Reports\disk.csv"
#>

[CmdletBinding()]
param (
    [ValidateRange(1, 99)][int]$WarnPercent     = 20,
    [ValidateRange(1, 99)][int]$CriticalPercent = 10,
    [string[]]$Drive,
    [string]$OutputPath
)

$ErrorActionPreference = 'SilentlyContinue'

$filter = 'DriveType = 3'
$disks  = Get-CimInstance Win32_LogicalDisk -Filter $filter |
          Where-Object { $_.Size -gt 0 }

if ($Drive) {
    $normalized = $Drive | ForEach-Object { $_.TrimEnd('\').ToUpper() }
    $disks = $disks | Where-Object { $normalized -contains $_.DeviceID.ToUpper() }
}

$results = $disks | ForEach-Object {
    $freePercent = [math]::Round($_.FreeSpace / $_.Size * 100, 1)
    $status      = if ($freePercent -le $CriticalPercent) { 'CRITICAL' }
                   elseif ($freePercent -le $WarnPercent) { 'WARNING'  }
                   else                                   { 'OK'       }
    [PSCustomObject]@{
        Drive       = $_.DeviceID
        Label       = $_.VolumeName
        'Total GB'  = [math]::Round($_.Size / 1GB, 2)
        'Used GB'   = [math]::Round(($_.Size - $_.FreeSpace) / 1GB, 2)
        'Free GB'   = [math]::Round($_.FreeSpace / 1GB, 2)
        'Free %'    = $freePercent
        Status      = $status
    }
}

Write-Host ""
Write-Host "  Get-DiskSpaceReport.ps1  |  Warn: <$WarnPercent%  Critical: <$CriticalPercent%" -ForegroundColor Cyan
Write-Host "  $('-' * 68)"
Write-Host ("  {0,-6} {1,-20} {2,10} {3,10} {4,10} {5,8}  {6}" -f 'Drive','Label','Total GB','Used GB','Free GB','Free %','Status')
Write-Host "  $('-' * 68)"

foreach ($r in $results) {
    $color = switch ($r.Status) {
        'CRITICAL' { 'Red'    }
        'WARNING'  { 'Yellow' }
        default    { 'Green'  }
    }
    Write-Host ("  {0,-6} {1,-20} {2,10} {3,10} {4,10} {5,7}%  {6}" -f `
        $r.Drive, $r.Label, $r.'Total GB', $r.'Used GB', $r.'Free GB', $r.'Free %', $r.Status) -ForegroundColor $color
}

Write-Host "  $('-' * 68)"
$warn     = @($results | Where-Object { $_.Status -eq 'WARNING'  }).Count
$critical = @($results | Where-Object { $_.Status -eq 'CRITICAL' }).Count
Write-Host "  Total: $($results.Count) drive(s)  |  Warning: $warn  |  Critical: $critical"
Write-Host ""

if ($OutputPath) {
    $results | Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Host "  Results saved: $OutputPath" -ForegroundColor Green
    Write-Host ""
}
