# Clear-PrintQueue.ps1

Clears stuck Windows print jobs by stopping the Print Spooler, purging the spool directory, and restarting the Spooler. Can target all queues or a specific printer.

## What It Does

Stops the Spooler service, removes all stalled jobs, and brings the Spooler back up — the standard fix for stuck print queues. When a printer name is specified, jobs for that queue are cancelled via WMI without a full Spooler restart. Reports how many jobs were cleared and confirms the Spooler came back up.

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
