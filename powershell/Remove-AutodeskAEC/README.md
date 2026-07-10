# Remove-AutodeskAEC.ps1

Completely removes Autodesk AEC Collection products from a Windows machine, including registry keys, shared components, licensing services, and all leftover files and per-user data. Supports targeted or full removal, dry-run mode, and optional silent reinstall after cleanup. Only operates on local drives.

## What It Does

Scans the Windows registry to detect installed Autodesk AEC Collection products (2019–2027), then — after showing a full pre-flight summary and requiring explicit confirmation — follows Autodesk's official 5-step clean uninstall sequence: silently uninstalls all products via ODIS (2022+) or MSI (legacy), runs `RemoveODIS.exe` and the AdskIdentityManager uninstaller to release locked files, removes the Autodesk Desktop Licensing Service, deletes all leftover directories across Program Files, ProgramData, and all user profiles (including Autodesk-named install residue in each user's `%TEMP%` folder), removes Autodesk registry keys, and finally uninstalls the Autodesk Genuine Service last (as required by Autodesk). An animated progress bar shows during each long-running step. A timestamped log is always written automatically.

## Easy Run (No PowerShell Knowledge Needed)

For users who are not comfortable with PowerShell, this folder includes `Run-Remove-AutodeskAEC.bat`. A ready-made zip (script + launcher + this README) is rebuilt automatically on every change and published at:

**<https://github.com/GalactiData/scripts/releases/download/remove-autodeskaec-latest/Remove-AutodeskAEC.zip>**

1. Download the zip (or copy this whole folder) to the target machine and **extract it** — the `.bat` and `.ps1` must stay together.
2. Double-click `Run-Remove-AutodeskAEC.bat`.
3. Accept the administrator (UAC) prompt.
4. Review the list of products/folders/registry keys shown, then type `YES` to proceed.

The launcher handles administrator elevation and PowerShell execution-policy / downloaded-file blocks automatically, and runs the script in full-removal mode (`-All`). The window stays open at the end so the summary and log path remain visible. For anything other than full removal (specific products, dry run, etc.), use the PowerShell command line below.

## Usage

```powershell
.\Remove-AutodeskAEC.ps1 [[-All] | [-Products <string[]>]] [-List] [-Install <path>]
                         [-WhatIf] [-Force] [-BackupRegistry]
                         [-LogPath <path>] [-Drive <letter>]
```

Must be run as **Administrator**.

## Options

| Parameter | Type | Description |
|-----------|------|-------------|
| `-All` | Switch | Remove every detected AEC Collection product |
| `-Products` | String[] | Target one or more products by partial name (case-insensitive) |
| `-List` | Switch | Display installed AEC products and exit — no changes made |
| `-Install` | String | Path to an Autodesk installer to run silently after cleanup |
| `-WhatIf` | Switch | Show all actions that would be taken without making any changes |
| `-Force` | Switch | Skip the interactive confirmation prompt |
| `-BackupRegistry` | Switch | Export registry keys to `.reg` files before deleting them |
| `-LogPath` | String | Log file path (default: `$env:TEMP\Remove-AutodeskAEC_<timestamp>.log`) |
| `-Drive` | String | Drive to clean (default: OS drive, e.g. `C:`). Network paths not permitted. |

## Examples

```powershell
# See what is installed before doing anything
.\Remove-AutodeskAEC.ps1 -List

# Dry run — show every action without making any changes
.\Remove-AutodeskAEC.ps1 -All -WhatIf

# Remove everything, with interactive confirmation
.\Remove-AutodeskAEC.ps1 -All

# Remove specific products only
.\Remove-AutodeskAEC.ps1 -Products "Revit", "Civil 3D"

# Remove everything and back up registry keys first
.\Remove-AutodeskAEC.ps1 -All -BackupRegistry

# Remove everything, then silently install a new version
.\Remove-AutodeskAEC.ps1 -All -Install "D:\Autodesk\Installer.exe"

# Unattended removal (e.g. in a deployment script) with a custom log path
.\Remove-AutodeskAEC.ps1 -All -Force -LogPath "C:\Logs\autodesk-removal.log"
```

## Hardcoded Defaults (Non-Interactive Use)

The script contains a `# CONFIGURATION` block near the top that lets you bake in default values so it can run with no arguments — useful for deployment scripts, scheduled tasks, or recurring use cases:

```powershell
$Config = @{
    All             = $false          # $true = always remove all products
    Products        = @()             # e.g. @('Revit', 'Civil 3D')
    Force           = $false          # $true = skip confirmation prompt
    BackupRegistry  = $false          # $true = always back up registry first
    LogPath         = ''              # e.g. 'C:\Logs\autodesk-removal.log'
    Drive           = ''              # e.g. 'D:' (empty = OS drive)
    Install         = ''              # e.g. 'D:\Autodesk\Installer.exe'
}
```

Command-line arguments always override anything set in `$Config`, so a pre-configured script can still be overridden on the fly.

## Notes

- The script always writes a log. If `-LogPath` is not specified, the log is created automatically in `%TEMP%` and its path is printed at startup.
- Before any destructive action, the script displays a full list of products, registry keys, and directories to be removed, followed by a warning that the action is irreversible. You must type `YES` exactly to proceed (bypassed by `-Force`).
- If any product uninstall is skipped (installer not found, GUID missing) or fails (non-success exit code from ODIS or msiexec), the script aborts before deleting any files or registry keys. Products that were not properly uninstalled are listed. Resolve them manually and re-run. MSI exit code 1605 ("product not installed") is tolerated, as sub-packages are often removed by their parent suite's uninstall first.
- Autodesk Identity Manager is removed via its bundled `uninstall.exe` when present, or via MSI (1.15.x+ has no `uninstall.exe`). For both Identity Manager and Genuine Service, any orphaned Add/Remove Programs entry is swept afterwards so no ghost entries remain in Settings > Apps.
- The script removes only Autodesk-owned files in `ProgramData\FLEXnet` (files matching `adsk*`). The FLEXnet directory itself is preserved as it may be shared with other software (e.g. Adobe).
- `-BackupRegistry` creates one `.reg` file per registry key, placed in the same directory as the log file.
- Products covered include: AutoCAD (all toolsets), Civil 3D, Revit, Navisworks, InfraWorks, ReCap Pro, Robot Structural Analysis, Advance Steel, Fabrication CADmep, FormIt, 3ds Max, Vehicle Tracking, Structural Bridge Design, Dynamo, App Manager, Batch Save Utility, Featured Apps, Save to Web and Mobile, and Autodesk shared components.
