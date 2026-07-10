# Get-PatchStatus.ps1

Reports Windows patch status: when the machine was last updated, pending updates, and whether a reboot is required. Read-only, with exit codes for monitoring.

## What It Does

Checks the installed hotfix history for the most recent update and flags the machine against configurable warning/critical age thresholds, queries the Windows Update Agent for updates waiting to be installed, and checks the three standard registry locations for a pending reboot (Component Based Servicing, Windows Update, pending file renames). Nothing is installed or changed. Suitable for patch compliance spot-checks, pre-maintenance reviews, or scheduled reporting via CSV.

## Easy Run (no PowerShell knowledge needed)

1. Copy the folder to the machine.
2. Double-click `Run-Get-PatchStatus.bat`.
3. Read the status summary. No administrator rights are needed and nothing is changed.

## Usage

```powershell
.\Get-PatchStatus.ps1 [options]
```

## Options

| Parameter | Type | Description |
|-----------|------|-------------|
| `-WarnDays` | Int | WARNING when the last update is older than this many days (default: 30) |
| `-CritDays` | Int | CRITICAL when the last update is older than this many days (default: 90) |
| `-SkipUpdateSearch` | Switch | Skip the online Windows Update search (much faster) |
| `-OutputPath` | String | Export the result to this CSV file |

## Examples

```powershell
# Full status check
.\Get-PatchStatus.ps1

# Relaxed thresholds
.\Get-PatchStatus.ps1 -WarnDays 45 -CritDays 120

# Fast offline check with CSV export for fleet collection
.\Get-PatchStatus.ps1 -SkipUpdateSearch -OutputPath "C:\Reports\patch-status.csv"
```

## Notes

- Exit codes: `0` = OK, `1` = WARNING (updates pending, reboot pending, or last update older than `-WarnDays`), `2` = CRITICAL (older than `-CritDays` or no update history found).
- The Windows Update search uses the same agent as the Settings app and can take a minute or more; use `-SkipUpdateSearch` when only age and reboot status matter.
- `Get-HotFix` covers OS-level updates (KBs); it does not include Microsoft Store or driver updates.
