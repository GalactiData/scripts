# Clear-PrintQueue.ps1

Clears stuck Windows print jobs by stopping the Print Spooler, purging the spool directory, and restarting the Spooler. Can target all queues or a specific printer.

## What It Does

Stops the Spooler service, removes all stalled jobs, and brings the Spooler back up — the standard fix for stuck print queues. When a printer name is specified, jobs for that queue are cancelled via WMI without a full Spooler restart. Reports how many jobs were cleared and confirms the Spooler came back up.

## Easy Run (No PowerShell Knowledge Needed)

For users who are not comfortable with PowerShell, this folder includes `Run-Clear-PrintQueue.bat`. A ready-made zip (script + launcher + this README) is rebuilt automatically on every change and published at:

**<https://github.com/GalactiData/scripts/releases/download/clear-printqueue-latest/Clear-PrintQueue.zip>**

1. Download the zip to the target machine and **extract it** — the `.bat` and `.ps1` must stay together.
2. Double-click `Run-Clear-PrintQueue.bat` and accept the administrator (UAC) prompt.
3. Confirm when asked. All stuck print jobs across every printer queue are cleared. (Targeting a single printer requires the PowerShell command line below.)

## Usage

```powershell
.\Clear-PrintQueue.ps1 [[-PrinterName] <string>] [-WhatIf] [-Force] [[-LogPath] <path>]
```

Must be run as **Administrator**.

## Options

| Parameter | Type | Description |
|-----------|------|-------------|
| `-PrinterName` | String | Target a specific printer by partial name. Clears all queues if omitted. |
| `-WhatIf` | Switch | Show what would be done without making any changes |
| `-Force` | Switch | Skip the confirmation prompt |
| `-LogPath` | String | Log file path. Defaults to a timestamped file in `%TEMP%` |

## Hardcoded Defaults

A `$Config` block at the top of the script lets you embed defaults for non-interactive or scripted use.

## Examples

```powershell
# Clear all print queues
.\Clear-PrintQueue.ps1

# Preview without changes
.\Clear-PrintQueue.ps1 -WhatIf

# Target a specific printer
.\Clear-PrintQueue.ps1 -PrinterName "HP LaserJet"

# Unattended (e.g. remote execution)
.\Clear-PrintQueue.ps1 -Force -LogPath "C:\Logs\printqueue.log"
```

## Notes

- When no `-PrinterName` is given: Spooler is stopped, all files in `C:\Windows\System32\spool\PRINTERS\` are deleted, Spooler is restarted. This clears every queued job across all printers.
- When `-PrinterName` is given: jobs are cancelled via WMI without restarting the Spooler, so other printers are unaffected.
