# Invoke-TempCleanup.ps1

Frees disk space by cleaning temp files, browser caches, and the Windows Update download cache. Reports estimated space freed. Supports `-WhatIf` to preview what would be removed.

## What It Does

Targets well-known temporary and cache directories across all user profiles on the machine: Windows Temp, user Temp folders, Prefetch, Chrome/Edge/Firefox caches, the Windows Update download cache, and the Recycle Bin. Cleans them silently and logs everything to a timestamped log file. Must be run as Administrator to access all locations.

## Usage

```powershell
.\Invoke-TempCleanup.ps1 [[-Targets] <string[]>] [[-OlderThanDays] <int>]
                         [-WhatIf] [-Force] [[-LogPath] <path>]
```

## Options

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Targets` | String[] | Which areas to clean. Default: all. Valid values: `WindowsTemp`, `UserTemp`, `Prefetch`, `BrowserCache`, `WindowsUpdate`, `RecycleBin` |
| `-OlderThanDays` | Int | Only remove files older than this many days. Default: 0 (all files) |
| `-WhatIf` | Switch | Show what would be removed without deleting anything |
| `-Force` | Switch | Skip the confirmation prompt |
| `-LogPath` | String | Log file path. Defaults to a timestamped file in `%TEMP%` |

## Hardcoded Defaults

A `$Config` block at the top of the script lets you embed defaults for non-interactive or scheduled use. Any command-line argument overrides the config.

## Examples

```powershell
# Interactive cleanup of all areas
.\Invoke-TempCleanup.ps1

# Preview what would be removed
.\Invoke-TempCleanup.ps1 -WhatIf

# Clean only temp folders, files older than 7 days
.\Invoke-TempCleanup.ps1 -Targets WindowsTemp, UserTemp -OlderThanDays 7

# Unattended cleanup (e.g. scheduled task)
.\Invoke-TempCleanup.ps1 -Force -LogPath "C:\Logs\cleanup.log"

# Clean everything except browser caches
.\Invoke-TempCleanup.ps1 -Targets WindowsTemp, UserTemp, Prefetch, WindowsUpdate, RecycleBin
```
