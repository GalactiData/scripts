#Requires -Version 5.1

<#
.SYNOPSIS
    Collects a full hardware and software inventory snapshot of the local machine.

.DESCRIPTION
    Gathers CPU, RAM, disk, GPU, OS, network, and installed software details.
    Outputs to the console, CSV files, or a self-contained HTML report.

.PARAMETER OutputPath
    Path for the output file. For CSV, used as the base name — one file per section
    is created in the same directory (e.g. inventory-system.csv, inventory-software.csv).
    For HTML, the full file path (e.g. C:\Reports\inventory.html).

.PARAMETER Format
    Output format: Console (default), CSV, or HTML.

.PARAMETER SkipSoftware
    Skip collecting the installed software list. Speeds up the run significantly.

.EXAMPLE
    .\Get-SystemInventory.ps1

.EXAMPLE
    .\Get-SystemInventory.ps1 -Format HTML -OutputPath "C:\Reports\inventory.html"

.EXAMPLE
    .\Get-SystemInventory.ps1 -Format CSV -OutputPath "C:\Reports\inventory.csv"

.EXAMPLE
    .\Get-SystemInventory.ps1 -SkipSoftware
#>

[CmdletBinding()]
param (
    [string]$OutputPath,
    [ValidateSet('Console', 'CSV', 'HTML')]
    [string]$Format = 'Console',
    [switch]$SkipSoftware
)

$ErrorActionPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Data collection
# ---------------------------------------------------------------------------
function Get-OsInfo {
    $os     = Get-CimInstance Win32_OperatingSystem
    $cs     = Get-CimInstance Win32_ComputerSystem
    $bios   = Get-CimInstance Win32_BIOS
    $uptime = (Get-Date) - $os.LastBootUpTime
    [PSCustomObject]@{
        ComputerName  = $env:COMPUTERNAME
        Manufacturer  = $cs.Manufacturer
        Model         = $cs.Model
        SerialNumber  = $bios.SerialNumber
        Domain        = $cs.Domain
        OS           = $os.Caption
        Build        = $os.BuildNumber
        Version      = $os.Version
        Architecture = $os.OSArchitecture
        InstallDate  = $os.InstallDate.ToString('yyyy-MM-dd')
        LastBoot     = $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')
        Uptime       = "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
    }
}

function Get-CpuInfo {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    [PSCustomObject]@{
        Name         = $cpu.Name.Trim()
        Cores        = $cpu.NumberOfCores
        LogicalCores = $cpu.NumberOfLogicalProcessors
        MaxSpeedMHz  = $cpu.MaxClockSpeed
        Architecture = switch ($cpu.Architecture) { 0 { 'x86' } 9 { 'x64' } default { "$($cpu.Architecture)" } }
    }
}

function Get-RamInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    [PSCustomObject]@{
        TotalGB      = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        UsedGB       = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
        FreeGB       = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        UsedPercent  = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 1)
    }
}

function Get-DiskInfo {
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3' | ForEach-Object {
        if ($_.Size -gt 0) {
            [PSCustomObject]@{
                Drive       = $_.DeviceID
                Label       = $_.VolumeName
                TotalGB     = [math]::Round($_.Size / 1GB, 2)
                UsedGB      = [math]::Round(($_.Size - $_.FreeSpace) / 1GB, 2)
                FreeGB      = [math]::Round($_.FreeSpace / 1GB, 2)
                FreePercent = [math]::Round($_.FreeSpace / $_.Size * 100, 1)
            }
        }
    }
}

function Get-GpuInfo {
    Get-CimInstance Win32_VideoController | ForEach-Object {
        [PSCustomObject]@{
            Name          = $_.Name
            VRAM_MB       = if ($_.AdapterRAM) { [math]::Round($_.AdapterRAM / 1MB, 0) } else { 'N/A' }
            DriverVersion = $_.DriverVersion
        }
    }
}

function Get-NetworkInfo {
    Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
        $iface = $_
        $ips   = Get-NetIPAddress -InterfaceIndex $iface.InterfaceIndex |
                 Where-Object { $_.AddressFamily -in 'IPv4', 'IPv6' }
        foreach ($ip in $ips) {
            [PSCustomObject]@{
                Adapter       = $iface.Name
                Description   = $iface.InterfaceDescription
                MAC           = $iface.MacAddress
                IPAddress     = $ip.IPAddress
                PrefixLength  = $ip.PrefixLength
                AddressFamily = $ip.AddressFamily
            }
        }
    }
}

function Get-SoftwareInfo {
    $hives = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $list = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($hive in $hives) {
        Get-ItemProperty $hive | Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
            ForEach-Object {
                if ($seen.Add($_.DisplayName)) {
                    $list.Add([PSCustomObject]@{
                        Name        = $_.DisplayName
                        Version     = $_.DisplayVersion
                        Publisher   = $_.Publisher
                        InstallDate = $_.InstallDate
                    })
                }
            }
    }
    $list | Sort-Object Name
}

# ---------------------------------------------------------------------------
# HTML output
# ---------------------------------------------------------------------------
function Out-HtmlReport {
    param($Os, $Cpu, $Ram, $Disks, $Gpus, $Network, $Software, [string]$Path)

    $ts       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $diskRows = ($Disks | ForEach-Object {
        "<tr><td>$($_.Drive)</td><td>$($_.Label)</td><td>$($_.TotalGB)</td><td>$($_.UsedGB)</td><td>$($_.FreeGB)</td><td>$($_.FreePercent)%</td></tr>"
    }) -join "`n"
    $netRows  = ($Network | ForEach-Object {
        "<tr><td>$($_.Adapter)</td><td>$($_.MAC)</td><td>$($_.IPAddress)</td><td>$($_.AddressFamily)</td></tr>"
    }) -join "`n"
    $gpuRows  = ($Gpus | ForEach-Object {
        "<tr><td>$($_.Name)</td><td>$($_.VRAM_MB)</td><td>$($_.DriverVersion)</td></tr>"
    }) -join "`n"
    $swRows   = ($Software | ForEach-Object {
        "<tr><td>$($_.Name)</td><td>$($_.Version)</td><td>$($_.Publisher)</td><td>$($_.InstallDate)</td></tr>"
    }) -join "`n"

    @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>System Inventory — $($Os.ComputerName)</title>
<style>
  body  { font-family: Segoe UI, Arial, sans-serif; margin: 24px; background: #f4f4f4; color: #222; }
  h1    { color: #0078d4; margin-bottom: 4px; }
  h2    { color: #005a9e; border-bottom: 2px solid #0078d4; padding-bottom: 4px; margin-top: 32px; }
  table { border-collapse: collapse; width: 100%; background: #fff; margin-bottom: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
  th    { background: #0078d4; color: #fff; padding: 8px 14px; text-align: left; }
  td    { padding: 6px 14px; border-bottom: 1px solid #e8e8e8; }
  tr:hover td { background: #eaf4ff; }
  .meta { color: #777; margin-bottom: 24px; }
</style>
</head>
<body>
<h1>System Inventory</h1>
<p class="meta">Host: <strong>$($Os.ComputerName)</strong> &nbsp;|&nbsp; Generated: $ts</p>

<h2>System</h2>
<table>
  <tr><th>Property</th><th>Value</th></tr>
  <tr><td>Manufacturer</td><td>$($Os.Manufacturer)</td></tr>
  <tr><td>Model</td><td>$($Os.Model)</td></tr>
  <tr><td>Serial Number</td><td>$($Os.SerialNumber)</td></tr>
  <tr><td>Domain</td><td>$($Os.Domain)</td></tr>
  <tr><td>Operating System</td><td>$($Os.OS)</td></tr>
  <tr><td>Build</td><td>$($Os.Build)</td></tr>
  <tr><td>Architecture</td><td>$($Os.Architecture)</td></tr>
  <tr><td>Install Date</td><td>$($Os.InstallDate)</td></tr>
  <tr><td>Last Boot</td><td>$($Os.LastBoot)</td></tr>
  <tr><td>Uptime</td><td>$($Os.Uptime)</td></tr>
</table>

<h2>CPU</h2>
<table>
  <tr><th>Property</th><th>Value</th></tr>
  <tr><td>Model</td><td>$($Cpu.Name)</td></tr>
  <tr><td>Physical Cores</td><td>$($Cpu.Cores)</td></tr>
  <tr><td>Logical Processors</td><td>$($Cpu.LogicalCores)</td></tr>
  <tr><td>Max Speed (MHz)</td><td>$($Cpu.MaxSpeedMHz)</td></tr>
  <tr><td>Architecture</td><td>$($Cpu.Architecture)</td></tr>
</table>

<h2>Memory</h2>
<table>
  <tr><th>Total (GB)</th><th>Used (GB)</th><th>Free (GB)</th><th>Used %</th></tr>
  <tr><td>$($Ram.TotalGB)</td><td>$($Ram.UsedGB)</td><td>$($Ram.FreeGB)</td><td>$($Ram.UsedPercent)%</td></tr>
</table>

<h2>Disks</h2>
<table>
  <tr><th>Drive</th><th>Label</th><th>Total (GB)</th><th>Used (GB)</th><th>Free (GB)</th><th>Free %</th></tr>
  $diskRows
</table>

<h2>GPU</h2>
<table>
  <tr><th>Name</th><th>VRAM (MB)</th><th>Driver Version</th></tr>
  $gpuRows
</table>

<h2>Network Adapters (Active)</h2>
<table>
  <tr><th>Adapter</th><th>MAC</th><th>IP Address</th><th>Family</th></tr>
  $netRows
</table>

<h2>Installed Software ($($Software.Count) items)</h2>
<table>
  <tr><th>Name</th><th>Version</th><th>Publisher</th><th>Install Date</th></tr>
  $swRows
</table>
</body>
</html>
"@ | Set-Content -Path $Path -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  Get-SystemInventory.ps1" -ForegroundColor Cyan
Write-Host "  Collecting system information..." -ForegroundColor Cyan

$osInfo   = Get-OsInfo
$cpuInfo  = Get-CpuInfo
$ramInfo  = Get-RamInfo
$disks    = @(Get-DiskInfo)
$gpus     = @(Get-GpuInfo)
$network  = @(Get-NetworkInfo)
$software = if (-not $SkipSoftware) { @(Get-SoftwareInfo) } else { @() }

if ($Format -eq 'Console' -or -not $OutputPath) {
    Write-Host ""
    Write-Host "  ── SYSTEM ──────────────────────────────────────" -ForegroundColor Cyan
    $osInfo  | Format-List
    Write-Host "  ── CPU ─────────────────────────────────────────" -ForegroundColor Cyan
    $cpuInfo | Format-List
    Write-Host "  ── MEMORY ──────────────────────────────────────" -ForegroundColor Cyan
    $ramInfo | Format-List
    Write-Host "  ── DISKS ───────────────────────────────────────" -ForegroundColor Cyan
    $disks   | Format-Table -AutoSize
    Write-Host "  ── GPU ─────────────────────────────────────────" -ForegroundColor Cyan
    $gpus    | Format-Table -AutoSize
    Write-Host "  ── NETWORK (ACTIVE ADAPTERS) ───────────────────" -ForegroundColor Cyan
    $network | Format-Table -AutoSize
    if (-not $SkipSoftware) {
        Write-Host "  ── INSTALLED SOFTWARE ($($software.Count) items) ─────────────" -ForegroundColor Cyan
        $software | Format-Table -AutoSize
    }
}

if ($OutputPath) {
    switch ($Format) {
        'CSV' {
            $dir  = Split-Path $OutputPath -Parent
            $base = [System.IO.Path]::GetFileNameWithoutExtension($OutputPath)
            if (-not $dir) { $dir = '.' }
            $null = New-Item -ItemType Directory -Path $dir -Force
            $osInfo  | Export-Csv (Join-Path $dir "$base-system.csv")   -NoTypeInformation
            $cpuInfo | Export-Csv (Join-Path $dir "$base-cpu.csv")      -NoTypeInformation
            $ramInfo | Export-Csv (Join-Path $dir "$base-memory.csv")   -NoTypeInformation
            $disks   | Export-Csv (Join-Path $dir "$base-disks.csv")    -NoTypeInformation
            $gpus    | Export-Csv (Join-Path $dir "$base-gpu.csv")      -NoTypeInformation
            $network | Export-Csv (Join-Path $dir "$base-network.csv")  -NoTypeInformation
            if (-not $SkipSoftware) {
                $software | Export-Csv (Join-Path $dir "$base-software.csv") -NoTypeInformation
            }
            Write-Host "  CSV files saved to: $dir" -ForegroundColor Green
        }
        'HTML' {
            $dir = Split-Path $OutputPath -Parent
            if ($dir) { $null = New-Item -ItemType Directory -Path $dir -Force }
            Out-HtmlReport -Os $osInfo -Cpu $cpuInfo -Ram $ramInfo -Disks $disks `
                -Gpus $gpus -Network $network -Software $software -Path $OutputPath
            Write-Host "  HTML report saved: $OutputPath" -ForegroundColor Green
        }
    }
}

Write-Host ""
