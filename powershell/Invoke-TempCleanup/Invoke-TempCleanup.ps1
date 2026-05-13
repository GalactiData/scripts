#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
.SYNOPSIS
    Frees disk space by cleaning temp files, browser caches, and Windows update cache.

.DESCRIPTION
    Removes files from well-known temporary and cache locations on a Windows machine.
    Reports total space freed. Supports -WhatIf to preview what would be removed
    without making any changes.

.PARAMETER Targets
    Which areas to clean. Defaults to all. Valid values:
    WindowsTemp, UserTemp, Prefetch, BrowserCache, WindowsUpdate, RecycleBin.

.PARAMETER OlderThanDays
    Only remove files older than this many days. Default: 0 (remove all).

.PARAMETER WhatIf
    Show what would be removed without deleting anything.

.PARAMETER Force
    Skip the confirmation prompt.

.PARAMETER LogPath
    Write a cleanup log to this file. Defaults to a timestamped file in $env:TEMP.

.EXAMPLE
    .\Invoke-TempCleanup.ps1

.EXAMPLE
    .\Invoke-TempCleanup.ps1 -WhatIf

.EXAMPLE
    .\Invoke-TempCleanup.ps1 -Targets WindowsTemp, UserTemp -OlderThanDays 7

.EXAMPLE
    .\Invoke-TempCleanup.ps1 -Force -LogPath "C:\Logs\cleanup.log"
#>

[CmdletBinding()]
param (
    [ValidateSet('WindowsTemp', 'UserTemp', 'Prefetch', 'BrowserCache', 'WindowsUpdate', 'RecycleBin')]
    [string[]]$Targets = @('WindowsTemp', 'UserTemp', 'Prefetch', 'BrowserCache', 'WindowsUpdate', 'RecycleBin'),
    [int]$OlderThanDays = 0,
    [switch]$WhatIf,
    [switch]$Force,
    [string]$LogPath
)

# ===========================================================================
# CONFIGURATION — edit to set persistent defaults
# ===========================================================================
$Config = @{
    Targets       = @()   # Leave empty to use param default (all targets)
    OlderThanDays = -1    # -1 = use param default
    Force         = $false
    LogPath       = ''
}
# ===========================================================================

$ErrorActionPreference = 'SilentlyContinue'

# Apply config defaults
if (-not $PSBoundParameters.ContainsKey('Targets')       -and $Config.Targets.Count -gt 0)  { $Targets       = $Config.Targets }
if (-not $PSBoundParameters.ContainsKey('OlderThanDays') -and $Config.OlderThanDays -ge 0)  { $OlderThanDays = $Config.OlderThanDays }
if (-not $PSBoundParameters.ContainsKey('Force')         -and $Config.Force)                { $Force         = [switch]$true }
if (-not $PSBoundParameters.ContainsKey('LogPath')       -and $Config.LogPath)              { $LogPath       = $Config.LogPath }

if (-not $LogPath) {
    $ts      = Get-Date -Format 'yyyyMMdd_HHmmss'
    $LogPath = Join-Path $env:TEMP "Invoke-TempCleanup_$ts.log"
}
$null = New-Item -ItemType File -Path $LogPath -Force

function Write-Log {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    Write-Host "  $Message"
}

function Get-FolderSize([string]$Path) {
    if (-not (Test-Path $Path)) { return 0 }
    (Get-ChildItem $Path -Recurse -Force | Measure-Object -Property Length -Sum).Sum
}

function Remove-OldFiles {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) { return 0 }

    $cutoff = if ($OlderThanDays -gt 0) { (Get-Date).AddDays(-$OlderThanDays) } else { $null }
    $files  = Get-ChildItem $Path -Recurse -Force | Where-Object {
        -not $_.PSIsContainer -and (-not $cutoff -or $_.LastWriteTime -lt $cutoff)
    }

    $bytes = ($files | Measure-Object -Property Length -Sum).Sum

    if ($WhatIf) {
        Write-Log "WHATIF: Would remove $($files.Count) file(s) ($([math]::Round($bytes/1MB,2)) MB) from $Label"
        return $bytes
    }

    $removed = 0
    foreach ($f in $files) {
        try { Remove-Item $f.FullName -Force; $removed += $f.Length } catch { Write-Log "Skipped locked file: $($f.Name)" }
    }
    # Remove directories only if they are empty (avoids prompt on non-empty dirs)
    Get-ChildItem $Path -Recurse -Force | Where-Object { $_.PSIsContainer } |
        Sort-Object FullName -Descending |
        ForEach-Object {
            if (-not (Get-ChildItem $_.FullName -Force -ErrorAction SilentlyContinue)) {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }

    Write-Log "Cleaned ${Label}: removed $([math]::Round($removed/1MB,2)) MB"
    return $removed
}

Write-Host ""
Write-Host "  Invoke-TempCleanup.ps1" -ForegroundColor Cyan
Write-Host "  Log: $LogPath"
Write-Log "Started. Targets=$($Targets -join ',') OlderThanDays=$OlderThanDays WhatIf=$($WhatIf.IsPresent)"

if (-not $WhatIf -and -not $Force) {
    $answer = Read-Host "`n  This will delete files. Type YES to continue or anything else to abort"
    if ($answer -cne 'YES') {
        Write-Host "  Aborted. No files were removed." -ForegroundColor Green
        exit 0
    }
}

# Measure before
$driveBefore = (Get-PSDrive C).Free

$freed = 0

foreach ($target in $Targets) {
    switch ($target) {
        'WindowsTemp' {
            $freed += Remove-OldFiles "$env:windir\Temp" 'Windows Temp'
        }
        'UserTemp' {
            Get-ChildItem 'C:\Users' -Directory | ForEach-Object {
                $freed += Remove-OldFiles "$($_.FullName)\AppData\Local\Temp" "UserTemp ($($_.Name))"
            }
        }
        'Prefetch' {
            $freed += Remove-OldFiles "$env:windir\Prefetch" 'Prefetch'
        }
        'BrowserCache' {
            Get-ChildItem 'C:\Users' -Directory | ForEach-Object {
                $user = $_.FullName
                $userName = $_.Name

                # Chrome
                $freed += Remove-OldFiles "$user\AppData\Local\Google\Chrome\User Data\Default\Cache"      "Chrome Cache ($userName)"
                $freed += Remove-OldFiles "$user\AppData\Local\Google\Chrome\User Data\Default\Code Cache"  "Chrome Code Cache ($userName)"

                # Edge
                $freed += Remove-OldFiles "$user\AppData\Local\Microsoft\Edge\User Data\Default\Cache"      "Edge Cache ($userName)"
                $freed += Remove-OldFiles "$user\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache"  "Edge Code Cache ($userName)"

                # Brave
                $freed += Remove-OldFiles "$user\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Cache"      "Brave Cache ($userName)"
                $freed += Remove-OldFiles "$user\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Code Cache"  "Brave Code Cache ($userName)"

                # Opera
                $freed += Remove-OldFiles "$user\AppData\Roaming\Opera Software\Opera Stable\Cache"       "Opera Cache ($userName)"
                $freed += Remove-OldFiles "$user\AppData\Local\Opera Software\Opera Stable\Cache"         "Opera Cache Local ($userName)"

                # Opera GX
                $freed += Remove-OldFiles "$user\AppData\Roaming\Opera Software\Opera GX Stable\Cache"    "Opera GX Cache ($userName)"
                $freed += Remove-OldFiles "$user\AppData\Local\Opera Software\Opera GX Stable\Cache"      "Opera GX Cache Local ($userName)"

                # Vivaldi
                $freed += Remove-OldFiles "$user\AppData\Local\Vivaldi\User Data\Default\Cache"      "Vivaldi Cache ($userName)"
                $freed += Remove-OldFiles "$user\AppData\Local\Vivaldi\User Data\Default\Code Cache"  "Vivaldi Code Cache ($userName)"

                # Internet Explorer
                $freed += Remove-OldFiles "$user\AppData\Local\Microsoft\Windows\INetCache"  "IE Cache ($userName)"

                # Firefox (profile-based cache)
                $ffProfiles = "$user\AppData\Local\Mozilla\Firefox\Profiles"
                if (Test-Path $ffProfiles) {
                    Get-ChildItem $ffProfiles -Directory | ForEach-Object {
                        $freed += Remove-OldFiles "$($_.FullName)\cache2" "Firefox Cache ($userName)"
                    }
                }

                # Waterfox (Firefox-based)
                $wfProfiles = "$user\AppData\Local\Waterfox\Profiles"
                if (Test-Path $wfProfiles) {
                    Get-ChildItem $wfProfiles -Directory | ForEach-Object {
                        $freed += Remove-OldFiles "$($_.FullName)\cache2" "Waterfox Cache ($userName)"
                    }
                }

                # LibreWolf (Firefox-based)
                $lwProfiles = "$user\AppData\Local\LibreWolf\Profiles"
                if (Test-Path $lwProfiles) {
                    Get-ChildItem $lwProfiles -Directory | ForEach-Object {
                        $freed += Remove-OldFiles "$($_.FullName)\cache2" "LibreWolf Cache ($userName)"
                    }
                }
            }
        }
        'WindowsUpdate' {
            # Stop Windows Update service before clearing download cache
            if (-not $WhatIf) { Stop-Service wuauserv -Force }
            $freed += Remove-OldFiles "$env:windir\SoftwareDistribution\Download" 'Windows Update Cache'
            if (-not $WhatIf) { Start-Service wuauserv }
        }
        'RecycleBin' {
            if ($WhatIf) {
                Write-Log "WHATIF: Would empty the Recycle Bin"
            } else {
                try {
                    $shell = New-Object -ComObject Shell.Application
                    $bin   = $shell.Namespace(0xA)
                    $binSize = ($bin.Items() | Measure-Object -Property Size -Sum).Sum
                    $bin.Items() | ForEach-Object { $shell.Namespace(0xA).ParseName($_.Path).InvokeVerb('delete') }
                    $freed += $binSize
                    Write-Log "Emptied Recycle Bin: $([math]::Round($binSize/1MB,2)) MB"
                } catch {
                    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                    Write-Log "Emptied Recycle Bin"
                }
            }
        }
    }
}

$driveAfter = (Get-PSDrive C).Free
$actual     = $driveAfter - $driveBefore

$modeLabel = if ($WhatIf) { ' (WhatIf — no files deleted)' } else { '' }
Write-Host ""
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  SUMMARY$modeLabel"
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  Estimated freed : $([math]::Round($freed/1MB,2)) MB"
if (-not $WhatIf) {
    Write-Host "  Actual C: freed : $([math]::Round($actual/1MB,2)) MB"
}
Write-Host "  Log             : $LogPath"
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

Write-Log "Complete. EstimatedFreed=$([math]::Round($freed/1MB,2))MB"
