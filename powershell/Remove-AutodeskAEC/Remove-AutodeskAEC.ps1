#Requires -RunAsAdministrator
#Requires -Version 5.1

<#
.SYNOPSIS
    Completely removes Autodesk AEC Collection products from a Windows machine.

.DESCRIPTION
    Detects and removes Autodesk AEC Collection products including registry keys,
    program files, shared components, licensing services, and per-user data.
    Supports full removal, targeted removal by name, a dry-run mode, and optional
    silent reinstall after cleanup. Only operates on local drives.

.PARAMETER All
    Remove all detected AEC Collection products.

.PARAMETER Products
    One or more product name strings (partial match, case-insensitive) to target.
    Use -List first to see exact names.

.PARAMETER List
    Scan and display installed AEC products with version and installer type. No changes made.

.PARAMETER Install
    Path to an Autodesk ODIS Installer.exe or Setup.exe to run silently after cleanup.

.PARAMETER WhatIf
    Show every action that would be taken without making any changes.

.PARAMETER Force
    Skip the interactive YES/NO confirmation prompt. The pre-flight summary and
    warning banner are still written to the log.

.PARAMETER LogPath
    Full path for the log file. Defaults to a timestamped file in $env:TEMP.

.PARAMETER BackupRegistry
    Export all targeted Autodesk registry keys to .reg files before deleting them.
    Backup files are placed alongside the log file.

.PARAMETER Drive
    Drive letter to target for file cleanup (e.g. C:). Must be a local drive.
    Defaults to the OS drive ($env:SystemDrive). Network paths are not permitted.

.EXAMPLE
    .\Remove-AutodeskAEC.ps1 -List

.EXAMPLE
    .\Remove-AutodeskAEC.ps1 -All -WhatIf

.EXAMPLE
    .\Remove-AutodeskAEC.ps1 -All

.EXAMPLE
    .\Remove-AutodeskAEC.ps1 -Products "Revit", "Civil 3D"

.EXAMPLE
    .\Remove-AutodeskAEC.ps1 -All -BackupRegistry

.EXAMPLE
    .\Remove-AutodeskAEC.ps1 -All -Install "D:\Autodesk\Installer.exe"

.EXAMPLE
    .\Remove-AutodeskAEC.ps1 -All -Force -LogPath "C:\Logs\autodesk-removal.log"
#>

[CmdletBinding()]
param (
    [switch]$All,
    [string[]]$Products,
    [switch]$List,
    [string]$Install,
    [switch]$WhatIf,
    [switch]$Force,
    [string]$LogPath,
    [switch]$BackupRegistry,
    [string]$Drive = $env:SystemDrive
)

# ===========================================================================
# CONFIGURATION
# Edit these values to embed defaults directly in the script.
# Any value set here is used only when the matching parameter is NOT passed
# on the command line — explicit arguments always take precedence.
# ===========================================================================
$Config = @{
    # Set to $true to always target all AEC products (equivalent to -All)
    All             = $false

    # Product names to always target when -Products is not passed.
    # Partial names, case-insensitive. Example: @('Revit', 'Civil 3D')
    Products        = @()

    # Set to $true to skip the confirmation prompt (equivalent to -Force)
    Force           = $false

    # Set to $true to always back up registry keys before deleting them
    BackupRegistry  = $false

    # Fixed log file path. Leave empty to auto-generate in $env:TEMP.
    # Example: 'C:\Logs\autodesk-removal.log'
    LogPath         = ''

    # Target drive for file cleanup. Leave empty to use the OS drive.
    # Example: 'D:'
    Drive           = ''

    # Path to an Autodesk installer to run silently after cleanup.
    # Leave empty to skip reinstall. Example: 'D:\Autodesk\Installer.exe'
    Install         = ''
}
# ===========================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# AEC Collection product name keywords (2019–2027)
# ---------------------------------------------------------------------------
$script:AecKeywords = @(
    'AutoCAD',
    'Civil 3D',
    'Revit',
    'Navisworks',
    'InfraWorks',
    'ReCap',
    'Robot Structural Analysis',
    'Advance Steel',
    'Fabrication CADmep',
    'FormIt',
    '3ds Max',
    'Vehicle Tracking',
    'Structural Bridge Design',
    'Dynamo',
    'Autodesk Rendering',
    'Autodesk Access',
    'Autodesk Desktop App',
    'Autodesk Single Sign On',
    'Autodesk Identity Manager',
    'Autodesk Licensing',
    'Autodesk Genuine Service'
)

# Registry keys targeted for removal
$script:RegistryKeys = @(
    'HKLM:\SOFTWARE\Autodesk',
    'HKLM:\SOFTWARE\WOW6432Node\Autodesk',
    'HKCU:\SOFTWARE\Autodesk',
    'HKLM:\SOFTWARE\FLEXlm License Manager',
    'HKLM:\SOFTWARE\WOW6432Node\FLEXlm License Manager'
)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
    switch ($Level) {
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Host "  ERROR: $Message" -ForegroundColor Red }
        default { Write-Host "  $Message" }
    }
}

# ---------------------------------------------------------------------------
# Product discovery
# ---------------------------------------------------------------------------
function Get-InstalledAutodeskProducts {
    $hives = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $found = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seen  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($hive in $hives) {
        $entries = Get-ItemProperty $hive -ErrorAction SilentlyContinue |
            Where-Object { $_.PSObject.Properties['Publisher'] -and $_.Publisher -like '*Autodesk*' -and $_.PSObject.Properties['DisplayName'] -and $_.DisplayName }

        foreach ($entry in $entries) {
            $name = $entry.DisplayName
            if ($seen.Contains($name)) { continue }
            $isAec = $script:AecKeywords | Where-Object { $name -like "*$_*" }
            if (-not $isAec) { continue }
            $null = $seen.Add($name)
            $uninstallStr = if ($entry.PSObject.Properties['UninstallString']) { $entry.UninstallString } else { '' }
            $isOdis = ($uninstallStr -like '*AdODIS*') -or
                      ($uninstallStr -like '*Installer.exe*' -and $uninstallStr -like '*uninstall*')
            $found.Add([PSCustomObject]@{
                Name            = $name
                Version         = $entry.DisplayVersion
                GUID            = $entry.PSChildName
                UninstallString = $uninstallStr
                IsODIS          = [bool]$isOdis
            })
        }
    }
    return $found
}

# ---------------------------------------------------------------------------
# Confirmation gate
# ---------------------------------------------------------------------------
function Confirm-Proceed {
    param([System.Collections.Generic.List[PSCustomObject]]$TargetProducts)

    $productLines = ($TargetProducts | ForEach-Object {
        "    - $($_.Name) $($_.Version)  [$( if ($_.IsODIS) { 'ODIS' } else { 'MSI' } )]"
    }) -join "`n"

    $regLines = ($script:RegistryKeys | ForEach-Object { "    - $_" }) -join "`n"

    $baseDirs = @(
        "$Drive\Program Files\Autodesk",
        "$Drive\Program Files (x86)\Autodesk",
        "$Drive\Program Files (x86)\Common Files\Autodesk Shared",
        "$Drive\ProgramData\Autodesk",
        "$Drive\Autodesk",
        "$Drive\Users\*\AppData\Roaming\Autodesk",
        "$Drive\Users\*\AppData\Local\Autodesk",
        "$Drive\Users\*\AppData\LocalLow\Autodesk",
        "$Drive\ProgramData\FLEXnet\adsk* (files only)"
    )
    $dirLines = ($baseDirs | ForEach-Object { "    - $_" }) -join "`n"

    $summary = @"

  ┌─ PRODUCTS TO UNINSTALL ($($TargetProducts.Count)) ──────────────────────────────
$productLines

  ├─ REGISTRY KEYS TO DELETE ─────────────────────────────────────
$regLines

  ├─ DIRECTORIES TO REMOVE ───────────────────────────────────────
$dirLines

  └─ LOG FILE ────────────────────────────────────────────────────
    $script:LogPath
"@

    $banner = @"

  ╔══════════════════════════════════════════════════════════════╗
  ║   WARNING: THE FOLLOWING ACTIONS ARE IRREVERSIBLE.          ║
  ║   Once confirmed, there is no stopping or rolling back.     ║
  ║   Review the list above carefully before continuing.        ║
  ╚══════════════════════════════════════════════════════════════╝
"@

    Write-Host $summary
    Write-Host $banner -ForegroundColor Yellow
    Write-Log $summary
    Write-Log "Destructive action gate reached. Force=$($Force.IsPresent)"

    if ($Force) {
        Write-Host "`n  -Force specified. Proceeding without prompt.`n" -ForegroundColor Cyan
        Write-Log "-Force: skipping confirmation prompt."
        return $true
    }

    $answer = Read-Host "`n  Type YES to continue or anything else to abort"
    if ($answer -ceq 'YES') {
        Write-Log "User confirmed. Proceeding."
        return $true
    }
    Write-Log "User did not confirm (input: '$answer'). Aborting with no changes."
    Write-Host "`n  Aborted. No changes were made.`n" -ForegroundColor Green
    return $false
}

# ---------------------------------------------------------------------------
# Stop Autodesk processes and services
# ---------------------------------------------------------------------------
function Stop-AutodeskProcesses {
    Write-Log "Stopping Autodesk processes..."
    $procNames = @(
        'acad', 'accore', 'revit', 'navisworks', 'infraworks',
        'recap', 'Civil3D', 'AdAppMgr', 'AdSSO', 'ADSSO',
        'AdskIdentityManager', 'AdskLicensingAgent'
    )
    foreach ($p in $procNames) {
        $procs = Get-Process -Name $p -ErrorAction SilentlyContinue
        if ($procs) {
            $procs | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Log "Stopped process: $p"
        }
    }

    Write-Log "Stopping Autodesk services..."
    $svcNames = @(
        'AdskLicensingService',
        'FlexNet Licensing Service 64',
        'FLEXnet Licensing Service',
        'Autodesk Genuine Service'
    )
    foreach ($s in $svcNames) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Stopped') {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Write-Log "Stopped service: $s"
        }
    }
}

# ---------------------------------------------------------------------------
# Uninstall a single product
# ---------------------------------------------------------------------------
function Invoke-AutodeskUninstall {
    param([PSCustomObject]$Product)

    $label = "'$($Product.Name)' $($Product.Version)"

    if ($WhatIf) {
        $method = if ($Product.IsODIS) { 'ODIS' } else { 'MSI' }
        Write-Log "WHATIF: Would uninstall $label via $method"
        Write-Log "WHATIF:   UninstallString = $($Product.UninstallString)"
        return
    }

    Write-Log "Uninstalling: $label"

    if ($Product.IsODIS) {
        $raw = $Product.UninstallString.Trim()
        if ($raw -match '^"([^"]+)"\s*(.*)$') {
            $exe  = $Matches[1]
            $args = $Matches[2].Trim()
        } elseif ($raw -match '^(\S+)\s*(.*)$') {
            $exe  = $Matches[1]
            $args = $Matches[2].Trim()
        } else {
            Write-Log "Cannot parse UninstallString for $label. Skipping." -Level 'WARN'
            return
        }

        if (-not (Test-Path $exe)) {
            Write-Log "ODIS installer not found at '$exe'. Skipping." -Level 'WARN'
            return
        }

        $proc = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru -NoNewWindow
        Write-Log "ODIS uninstall exit code: $($proc.ExitCode)"

    } else {
        # Legacy MSI — extract GUID from PSChildName or UninstallString
        $guid = $Product.GUID -replace '[{}]', ''
        if ($guid -notmatch '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$') {
            # Try to extract from UninstallString
            if ($Product.UninstallString -match '\{([0-9A-Fa-f-]{36})\}') {
                $guid = $Matches[1]
            } else {
                Write-Log "Cannot determine GUID for $label. Skipping." -Level 'WARN'
                return
            }
        }

        $msiArgs = "/X{$guid} /quiet /norestart /l*v `"$script:LogPath`""
        $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
        Write-Log "MSI uninstall exit code: $($proc.ExitCode)"
    }
}

# ---------------------------------------------------------------------------
# Remove Autodesk Desktop Licensing Service
# ---------------------------------------------------------------------------
function Remove-AutodeskLicensing {
    $licensingDir = "$Drive\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing"
    $uninstaller  = Join-Path $licensingDir 'uninstall.exe'

    if (-not (Test-Path $uninstaller)) {
        Write-Log "AdskLicensing uninstaller not found. Skipping licensing removal."
        return
    }

    if ($WhatIf) {
        Write-Log "WHATIF: Would run AdskLicensing uninstaller: $uninstaller"
        return
    }

    Write-Log "Removing Autodesk Desktop Licensing Service..."
    Start-Process -FilePath $uninstaller -Wait -NoNewWindow

    # Wait up to 60 s for the directory to empty
    $elapsed = 0
    while ($elapsed -lt 60) {
        if (-not (Test-Path $licensingDir) -or
            -not (Get-ChildItem $licensingDir -Recurse -ErrorAction SilentlyContinue)) {
            break
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }

    if (Test-Path $licensingDir) {
        Write-Log "Licensing directory still present after ${elapsed}s. Force-removing..." -Level 'WARN'
        Remove-Item $licensingDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Licensing service removal complete."
}

# ---------------------------------------------------------------------------
# Registry cleanup
# ---------------------------------------------------------------------------
function Remove-AutodeskRegistry {
    if ($BackupRegistry) {
        $logDir  = [System.IO.Path]::GetDirectoryName($script:LogPath)
        $logBase = [System.IO.Path]::GetFileNameWithoutExtension($script:LogPath)
        Write-Log "Backing up registry keys before deletion..."

        $keyIndex = 0
        foreach ($key in $script:RegistryKeys) {
            if (Test-Path $key) {
                $keyIndex++
                $backupFile = Join-Path $logDir "$logBase-registry-backup-$keyIndex.reg"
                $regPath    = $key -replace 'HKLM:\\', 'HKEY_LOCAL_MACHINE\' `
                                   -replace 'HKCU:\\', 'HKEY_CURRENT_USER\'
                $result = & reg export $regPath $backupFile /y 2>&1
                Write-Log "Backup: $key -> $backupFile"
            }
        }
    }

    if ($WhatIf) {
        foreach ($key in $script:RegistryKeys) {
            Write-Log "WHATIF: Would delete registry key: $key"
        }
        return
    }

    Write-Log "Removing Autodesk registry keys..."
    foreach ($key in $script:RegistryKeys) {
        if (Test-Path $key) {
            try {
                Remove-Item $key -Recurse -Force
                Write-Log "Deleted registry key: $key"
            } catch {
                Write-Log "Failed to delete $key : $_" -Level 'WARN'
            }
        } else {
            Write-Log "Registry key not present (skipped): $key"
        }
    }
}

# ---------------------------------------------------------------------------
# File system cleanup
# ---------------------------------------------------------------------------
function Remove-AutodeskFiles {
    $dirs = [System.Collections.Generic.List[string]]::new()
    $dirs.AddRange([string[]]@(
        "$Drive\Program Files\Autodesk",
        "$Drive\Program Files (x86)\Autodesk",
        "$Drive\Program Files (x86)\Common Files\Autodesk Shared",
        "$Drive\ProgramData\Autodesk",
        "$Drive\Autodesk"
    ))

    # Per-user AppData for every profile on this drive
    $usersRoot = "$Drive\Users"
    if (Test-Path $usersRoot) {
        Get-ChildItem $usersRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $dirs.Add("$($_.FullName)\AppData\Roaming\Autodesk")
            $dirs.Add("$($_.FullName)\AppData\Local\Autodesk")
            $dirs.Add("$($_.FullName)\AppData\LocalLow\Autodesk")
        }
    }

    if ($WhatIf) {
        foreach ($d in $dirs) { Write-Log "WHATIF: Would remove directory: $d" }
        Write-Log "WHATIF: Would remove adsk* files from $Drive\ProgramData\FLEXnet"
        return 0
    }

    Write-Log "Removing Autodesk directories..."
    $removed = 0
    foreach ($d in $dirs) {
        if (Test-Path $d) {
            try {
                Remove-Item $d -Recurse -Force
                Write-Log "Removed: $d"
                $removed++
            } catch {
                Write-Log "Failed to remove $d : $_" -Level 'WARN'
            }
        }
    }

    # FLEXnet — only remove Autodesk-specific files (adsk*), not the entire directory
    $flexNetDir = "$Drive\ProgramData\FLEXnet"
    if (Test-Path $flexNetDir) {
        Write-Log "Removing Autodesk FLEXnet files from $flexNetDir..."
        Get-ChildItem $flexNetDir -Filter 'adsk*' -Force -ErrorAction SilentlyContinue |
            ForEach-Object {
                try {
                    Remove-Item $_.FullName -Force
                    Write-Log "Removed FLEXnet file: $($_.Name)"
                    $removed++
                } catch {
                    Write-Log "Failed to remove FLEXnet file '$($_.Name)': $_" -Level 'WARN'
                }
            }
    }

    Write-Log "File cleanup complete. Items removed: $removed"
    return $removed
}

# ---------------------------------------------------------------------------
# Optional reinstall
# ---------------------------------------------------------------------------
function Install-AutodeskProduct {
    param([string]$InstallerPath)

    if (-not (Test-Path $InstallerPath)) {
        Write-Log "Installer not found: '$InstallerPath'" -Level 'ERROR'
        return
    }

    $fileName = Split-Path $InstallerPath -Leaf
    $isOdis   = $fileName -eq 'Installer.exe'
    $instArgs = if ($isOdis) { '--mode unattended' } else { '/quiet /norestart' }

    Write-Log "Starting install: $InstallerPath"
    Write-Log "Arguments: $instArgs"

    if ($WhatIf) {
        Write-Log "WHATIF: Would run '$InstallerPath' $instArgs"
        return
    }

    $proc = Start-Process -FilePath $InstallerPath -ArgumentList $instArgs -Wait -PassThru -NoNewWindow
    Write-Log "Install exit code: $($proc.ExitCode)"

    if ($proc.ExitCode -eq 0) {
        Write-Host "`n  Install completed successfully." -ForegroundColor Green
    } else {
        Write-Log "Install returned non-zero exit code $($proc.ExitCode). Check the log for details." -Level 'WARN'
    }
}

# ===========================================================================
# MAIN
# ===========================================================================

# Apply $Config defaults for any parameter not explicitly passed on the command line
if (-not $PSBoundParameters.ContainsKey('All')            -and $Config.All)                          { $All            = [switch]$true }
if (-not $PSBoundParameters.ContainsKey('Products')       -and $Config.Products.Count -gt 0)         { $Products        = $Config.Products }
if (-not $PSBoundParameters.ContainsKey('Force')          -and $Config.Force)                        { $Force           = [switch]$true }
if (-not $PSBoundParameters.ContainsKey('BackupRegistry') -and $Config.BackupRegistry)               { $BackupRegistry  = [switch]$true }
if (-not $PSBoundParameters.ContainsKey('LogPath')        -and $Config.LogPath)                      { $LogPath         = $Config.LogPath }
if (-not $PSBoundParameters.ContainsKey('Drive')          -and $Config.Drive)                        { $Drive           = $Config.Drive }
if (-not $PSBoundParameters.ContainsKey('Install')        -and $Config.Install)                      { $Install         = $Config.Install }

# Validate drive — must be a local drive letter, not a UNC path
if ($Drive -match '^\\\\') {
    Write-Error "Network paths are not allowed. Specify a local drive letter (e.g. C:)."
    exit 1
}
if ($Drive -notmatch '^[A-Za-z]:') {
    Write-Error "Drive must be a letter followed by a colon (e.g. C:). Got: '$Drive'"
    exit 1
}
$Drive = ($Drive.TrimEnd('\').TrimEnd('/')).ToUpper()

# Require at least one action
if (-not $All -and -not $Products -and -not $List -and -not $Install) {
    Write-Error "Specify at least one of: -All, -Products <names>, -List, -Install <path>"
    exit 1
}

# Initialise log file
if (-not $LogPath) {
    $ts      = Get-Date -Format 'yyyyMMdd_HHmmss'
    $LogPath = Join-Path $env:TEMP "Remove-AutodeskAEC_$ts.log"
}
$script:LogPath = $LogPath
$null = New-Item -ItemType File -Path $script:LogPath -Force -ErrorAction Stop

Write-Host ""
Write-Host "  Remove-AutodeskAEC.ps1" -ForegroundColor Cyan
Write-Host "  Log: $script:LogPath`n"
Write-Log "Script started. Drive=$Drive All=$($All.IsPresent) WhatIf=$($WhatIf.IsPresent) Force=$($Force.IsPresent)"

# Discover installed products
Write-Host "  Scanning for installed Autodesk AEC Collection products..." -ForegroundColor Cyan
$discovered = Get-InstalledAutodeskProducts
Write-Log "Discovery complete. Found $($discovered.Count) AEC product(s)."

# -List mode: report and exit
if ($List) {
    if ($discovered.Count -eq 0) {
        Write-Host "`n  No Autodesk AEC Collection products found.`n"
    } else {
        Write-Host "`n  Installed Autodesk AEC Collection Products:`n"
        $discovered | Format-Table -AutoSize -Property Name, Version,
            @{ Label = 'Type'; Expression = { if ($_.IsODIS) { 'ODIS' } else { 'MSI' } } },
            GUID
    }
    Write-Log "-List: displayed $($discovered.Count) product(s). Exiting."
    exit 0
}

# Select targets
$targets = [System.Collections.Generic.List[PSCustomObject]]::new()

if ($All) {
    $targets.AddRange([PSCustomObject[]]@($discovered))
} elseif ($Products) {
    $notFound = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $Products) {
        $matched = $discovered | Where-Object { $_.Name -like "*$p*" }
        if (-not $matched) {
            $notFound.Add($p)
            Write-Log "No installed product matched '$p'." -Level 'WARN'
            Write-Warning "No match for '$p'. Run -List to see installed product names."
        } else {
            foreach ($m in $matched) { $targets.Add($m) }
        }
    }
    if ($targets.Count -eq 0) {
        Write-Host "`n  No matching products found. Nothing to do.`n"
        Write-Log "No targets selected. Exiting."
        exit 0
    }
}

# Confirmation gate (skipped for -WhatIf since nothing destructive runs)
if ($targets.Count -gt 0 -and -not $WhatIf) {
    if (-not (Confirm-Proceed -TargetProducts $targets)) {
        exit 0
    }
}

# ── Execute ──────────────────────────────────────────────────────────────────
$failed = [System.Collections.Generic.List[string]]::new()

if ($targets.Count -gt 0) {
    if (-not $WhatIf) { Stop-AutodeskProcesses }

    foreach ($t in $targets) {
        try {
            Invoke-AutodeskUninstall -Product $t
        } catch {
            Write-Log "Error uninstalling '$($t.Name)': $_" -Level 'ERROR'
            $failed.Add($t.Name)
        }
    }

    Remove-AutodeskLicensing
    Remove-AutodeskRegistry
    Remove-AutodeskFiles | Out-Null
}

# Optional reinstall
if ($Install) {
    Write-Host "`n  Starting reinstall..." -ForegroundColor Cyan
    Install-AutodeskProduct -InstallerPath $Install
}

# ── Summary ───────────────────────────────────────────────────────────────────
$mode = if ($WhatIf) { ' (WhatIf - no changes made)' } else { '' }
Write-Host ""
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  SUMMARY$mode"
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  Products targeted : $($targets.Count)"
Write-Host "  Products failed   : $($failed.Count)"
if ($failed.Count -gt 0) {
    $failed | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
}
Write-Host "  Log               : $script:LogPath"
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

Write-Log "Script complete. Targeted=$($targets.Count) Failed=$($failed.Count)"
