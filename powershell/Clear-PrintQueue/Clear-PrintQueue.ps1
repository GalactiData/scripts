#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
.SYNOPSIS
    Clears stuck print jobs from one or all Windows print queues.

.DESCRIPTION
    Stops the Print Spooler service, removes all files from the spool directory
    (or cancels jobs for a specific printer using WMI), and restarts the Spooler.
    Reports how many jobs were cleared. One of the most common Windows support tasks.

.PARAMETER PrinterName
    Target a specific printer queue by name. Accepts partial name match.
    If omitted, all queued jobs across all printers are cleared.

.PARAMETER WhatIf
    Show what would be done without making any changes.

.PARAMETER Force
    Skip the confirmation prompt.

.PARAMETER LogPath
    Write a log to this file. Defaults to a timestamped file in $env:TEMP.

.EXAMPLE
    .\Clear-PrintQueue.ps1

.EXAMPLE
    .\Clear-PrintQueue.ps1 -WhatIf

.EXAMPLE
    .\Clear-PrintQueue.ps1 -PrinterName "HP LaserJet"

.EXAMPLE
    .\Clear-PrintQueue.ps1 -Force -LogPath "C:\Logs\printqueue.log"
#>

[CmdletBinding()]
param (
    [string]$PrinterName,
    [switch]$WhatIf,
    [switch]$Force,
    [string]$LogPath
)

# ===========================================================================
# CONFIGURATION — edit to set persistent defaults
# ===========================================================================
$Config = @{
    PrinterName = ''       # Target printer name, or '' for all
    Force       = $false
    LogPath     = ''
}
# ===========================================================================

$ErrorActionPreference = 'Continue'

# Apply config defaults
if (-not $PSBoundParameters.ContainsKey('PrinterName') -and $Config.PrinterName) { $PrinterName = $Config.PrinterName }
if (-not $PSBoundParameters.ContainsKey('Force')       -and $Config.Force)       { $Force       = [switch]$true }
if (-not $PSBoundParameters.ContainsKey('LogPath')     -and $Config.LogPath)     { $LogPath     = $Config.LogPath }

if (-not $LogPath) {
    $ts      = Get-Date -Format 'yyyyMMdd_HHmmss'
    $LogPath = Join-Path $env:TEMP "Clear-PrintQueue_$ts.log"
}
$null = New-Item -ItemType File -Path $LogPath -Force

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    if ($Level -eq 'WARN') { Write-Warning $Message }
    else                   { Write-Host "  $Message" }
}

$spoolDir = "$env:windir\System32\spool\PRINTERS"

Write-Host ""
Write-Host "  Clear-PrintQueue.ps1" -ForegroundColor Cyan
Write-Host "  Log: $LogPath"
Write-Host ""

# Show current jobs
$allJobs = @(Get-CimInstance Win32_PrintJob -ErrorAction SilentlyContinue)
if ($PrinterName) {
    $targetJobs = @($allJobs | Where-Object { $_.Name -like "*$PrinterName*" })
    Write-Host "  Matching printer: '$PrinterName'"
    Write-Host "  Jobs in queue   : $($targetJobs.Count)"
} else {
    $targetJobs = $allJobs
    $printers   = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue)
    Write-Host "  Printers installed: $($printers.Count)"
    Write-Host "  Total jobs in queue: $($targetJobs.Count)"
}

if ($targetJobs.Count -gt 0) {
    Write-Host ""
    $targetJobs | Format-Table -AutoSize -Property @{L='Printer';E={($_.Name -split ',')[0]}},
        @{L='Job';E={($_.Name -split ',')[1]}}, Owner, TotalPages, Status
}

if ($WhatIf) {
    Write-Log "WHATIF: Would stop Spooler, remove $($targetJobs.Count) job(s), restart Spooler"
    Write-Host "  WhatIf — no changes made.`n" -ForegroundColor Cyan
    exit 0
}

if (-not $Force) {
    $answer = Read-Host "  Type YES to clear the queue or anything else to abort"
    if ($answer -ne 'YES') {
        Write-Host "  Aborted. No changes made.`n" -ForegroundColor Green
        exit 0
    }
}

Write-Log "Stopping Print Spooler..."
# -ErrorAction Stop: if the Spooler can't be stopped, abort rather than try
# to wipe spool files that are still locked by the running service
try {
    Stop-Service -Name Spooler -Force -ErrorAction Stop
} catch {
    Write-Log "Could not stop the Print Spooler: $_" -Level 'WARN'
    exit 1
}
Start-Sleep -Seconds 2

$cleared = 0

if ($PrinterName) {
    # Targeted: cancel specific jobs via WMI without wiping the entire spool directory
    Write-Log "Cancelling jobs for printer matching '$PrinterName'..."
    $targetJobs | ForEach-Object {
        try {
            $_ | Remove-CimInstance -ErrorAction Stop
            $cleared++
            Write-Log "Cancelled: $($_.Name)"
        } catch {
            Write-Log "Failed to cancel '$($_.Name)': $_" -Level 'WARN'
        }
    }
} else {
    # Full clear: delete all spool files
    Write-Log "Clearing spool directory: $spoolDir"
    $spoolFiles = Get-ChildItem $spoolDir -Force -ErrorAction SilentlyContinue
    foreach ($f in $spoolFiles) {
        try   { Remove-Item $f.FullName -Force -ErrorAction Stop; $cleared++ }
        catch { Write-Log "Could not remove '$($f.Name)': $_" -Level 'WARN' }
    }
    Write-Log "Removed $cleared spool file(s)."
}

Write-Log "Starting Print Spooler..."
Start-Service -Name Spooler
Start-Sleep -Seconds 2

$spooler = Get-Service -Name Spooler
$status  = $spooler.Status

Write-Host ""
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  SUMMARY"
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  Jobs cleared   : $cleared"
if ($PrinterName) {
    Write-Host "  Target printer : $PrinterName"
}
$spoolerColor = if ($status -eq 'Running') { 'Green' } else { 'Red' }
Write-Host "  Spooler status : $status" -ForegroundColor $spoolerColor
Write-Host "  Log            : $LogPath"
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

Write-Log "Complete. Cleared=$cleared SpoolerStatus=$status"
