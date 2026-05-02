# Get-DiskSpaceReport.ps1

Reports disk usage across local Windows drives with configurable warning and critical thresholds. Output is color-coded in the console and optionally exported to CSV.

## What It Does

Queries all fixed local drives (or a specified subset) and displays total size, used space, free space, and percentage free. Drives below the warning threshold are shown in yellow; drives below the critical threshold are shown in red. Suitable for quick health checks, pre-maintenance reviews, or scheduled reporting.

## Usage

```powershell
.\Get-DiskSpaceReport.ps1 [[-WarnPercent] <int>] [[-CriticalPercent] <int>] [[-Drive] <string[]>] [[-OutputPath] <path>]
```

## Options

| Parameter | Type | Description |
|-----------|------|-------------|
| `-WarnPercent` | Int | Flag drives with less than this % free as WARNING (default: 20) |
| `-CriticalPercent` | Int | Flag drives with less than this % free as CRITICAL (default: 10) |
| `-Drive` | String[] | Check only these drives, e.g. `C:`, `D:`. Checks all if omitted. |
| `-OutputPath` | String | Export results to this CSV file path |

## Examples

```powershell
# Check all drives with default thresholds
.\Get-DiskSpaceReport.ps1

# Custom thresholds
.\Get-DiskSpaceReport.ps1 -WarnPercent 25 -CriticalPercent 15

# Check specific drives and save to CSV
.\Get-DiskSpaceReport.ps1 -Drive C:, D: -OutputPath "C:\Reports\disk.csv"
```

## Notes

- Only fixed local drives (DriveType = 3) are checked. Network and removable drives are excluded.
- Exit-friendly output — use with scheduled tasks or monitoring tools that parse stdout.
