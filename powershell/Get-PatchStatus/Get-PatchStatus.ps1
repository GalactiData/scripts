#Requires -Version 5.1

<#
.SYNOPSIS
    Reports Windows patch status: last installed update, pending updates, and pending reboot.

.DESCRIPTION
    Shows when the machine was last patched and flags it against warning/critical age
    thresholds, searches Windows Update for pending updates, and checks the standard
    registry locations for a pending reboot. Read-only — nothing is installed or changed.
    Optionally exports the result to CSV.

.PARAMETER WarnDays
    Flag the machine as WARNING when the last installed update is older than this
    many days. Default: 30.

.PARAMETER CritDays
    Flag the machine as CRITICAL when the last installed update is older than this
    many days. Default: 90.

.PARAMETER SkipUpdateSearch
    Skip the online Windows Update search for pending updates (much faster; the
    search can take a minute or more).

.PARAMETER OutputPath
    Path to export the result as a CSV file.

.EXAMPLE
    .\Get-PatchStatus.ps1

.EXAMPLE
    .\Get-PatchStatus.ps1 -WarnDays 45 -CritDays 120

.EXAMPLE
    .\Get-PatchStatus.ps1 -SkipUpdateSearch -OutputPath "C:\Reports\patch-status.csv"
#>

[CmdletBinding()]
param (
    [ValidateRange(1, 365)][int]$WarnDays  = 30,
    [ValidateRange(1, 3650)][int]$CritDays = 90,
    [switch]$SkipUpdateSearch,
    [string]$OutputPath
)

$ErrorActionPreference = 'Continue'

if ($WarnDays -ge $CritDays) {
    Write-Error "-WarnDays ($WarnDays) must be lower than -CritDays ($CritDays)."
    exit 1
}

Write-Host ""
Write-Host "  Get-PatchStatus.ps1  |  Warn: >$WarnDays days  Critical: >$CritDays days" -ForegroundColor Cyan
Write-Host "  Collecting patch information..." -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Last installed update
# ---------------------------------------------------------------------------
$lastHotfix = Get-HotFix -ErrorAction SilentlyContinue |
              Where-Object { $_.InstalledOn } |
              Sort-Object InstalledOn -Descending |
              Select-Object -First 1

if ($lastHotfix) {
    $daysSince = [int]((Get-Date) - $lastHotfix.InstalledOn).TotalDays
    $lastLabel = "$($lastHotfix.HotFixID) on $($lastHotfix.InstalledOn.ToString('yyyy-MM-dd')) ($daysSince days ago)"
} else {
    $daysSince = $null
    $lastLabel = 'No update history found'
}

# ---------------------------------------------------------------------------
# Pending reboot (standard registry locations)
# ---------------------------------------------------------------------------
$rebootReasons = [System.Collections.Generic.List[string]]::new()

if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
    $rebootReasons.Add('Component Based Servicing')
}
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
    $rebootReasons.Add('Windows Update')
}
$pfro = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
        -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
if ($pfro -and $pfro.PendingFileRenameOperations) {
    $rebootReasons.Add('Pending file renames')
}

$rebootPending = $rebootReasons.Count -gt 0

# ---------------------------------------------------------------------------
# Pending updates (Windows Update Agent COM search)
# ---------------------------------------------------------------------------
$pendingCount  = $null
$pendingTitles = @()

if (-not $SkipUpdateSearch) {
    Write-Host "  Searching Windows Update for pending updates (this can take a minute)..." -ForegroundColor Cyan
    try {
        $session  = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $result   = $searcher.Search('IsInstalled=0 and IsHidden=0')
        $pendingCount  = $result.Updates.Count
        $pendingTitles = @($result.Updates | ForEach-Object { $_.Title })
    } catch {
        Write-Warning "Windows Update search failed: $_"
    }
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
$status = 'OK'
if ($rebootPending -or ($pendingCount -gt 0)) { $status = 'WARNING' }
if ($null -ne $daysSince -and $daysSince -gt $WarnDays) { $status = 'WARNING' }
if (($null -eq $daysSince) -or ($daysSince -gt $CritDays)) { $status = 'CRITICAL' }

$statusColor = switch ($status) {
    'CRITICAL' { 'Red'    }
    'WARNING'  { 'Yellow' }
    default    { 'Green'  }
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
$os     = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$uptime = if ($os) { [int]((Get-Date) - $os.LastBootUpTime).TotalDays } else { $null }

$pendingLabel = if ($SkipUpdateSearch)         { 'Skipped (-SkipUpdateSearch)' }
                elseif ($null -eq $pendingCount) { 'Unknown (search failed)'   }
                else                             { "$pendingCount"             }
$rebootLabel  = if ($rebootPending) { "YES ($($rebootReasons -join ', '))" } else { 'No' }

Write-Host ""
Write-Host "  $('-' * 68)"
Write-Host ("  {0,-22} {1}" -f 'Computer',        $env:COMPUTERNAME)
if ($os) {
    Write-Host ("  {0,-22} {1}" -f 'OS',          "$($os.Caption) (build $($os.BuildNumber))")
    Write-Host ("  {0,-22} {1}" -f 'Last boot',   "$($os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm')) ($uptime days ago)")
}
Write-Host ("  {0,-22} {1}" -f 'Last update',     $lastLabel)
Write-Host ("  {0,-22} {1}" -f 'Pending updates', $pendingLabel)
Write-Host ("  {0,-22} {1}" -f 'Reboot pending',  $rebootLabel)
Write-Host "  $('-' * 68)"
Write-Host "  Status: $status" -ForegroundColor $statusColor
Write-Host ""

if ($pendingTitles.Count -gt 0) {
    Write-Host "  Pending updates:" -ForegroundColor Cyan
    $pendingTitles | Select-Object -First 15 | ForEach-Object { Write-Host "    - $_" }
    if ($pendingTitles.Count -gt 15) {
        Write-Host "    ... and $($pendingTitles.Count - 15) more"
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# CSV export
# ---------------------------------------------------------------------------
if ($OutputPath) {
    [PSCustomObject]@{
        Computer        = $env:COMPUTERNAME
        Timestamp       = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        LastUpdateId    = if ($lastHotfix) { $lastHotfix.HotFixID } else { '' }
        LastUpdateDate  = if ($lastHotfix) { $lastHotfix.InstalledOn.ToString('yyyy-MM-dd') } else { '' }
        DaysSinceUpdate = $daysSince
        PendingUpdates  = $pendingLabel
        RebootPending   = $rebootPending
        RebootReasons   = $rebootReasons -join '; '
        Status          = $status
    } | Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Host "  Results saved: $OutputPath" -ForegroundColor Green
    Write-Host ""
}

switch ($status) {
    'CRITICAL' { exit 2 }
    'WARNING'  { exit 1 }
    default    { exit 0 }
}
