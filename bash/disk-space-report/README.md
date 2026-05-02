# disk-space-report.sh

Reports disk usage across local Linux filesystems with configurable warning and critical thresholds. Color-coded output with exit codes for use in monitoring pipelines.

## What It Does

Reads all locally mounted filesystems (excluding pseudo-filesystems like `tmpfs`, `devtmpfs`, and `overlay`) and displays usage with color-coded status: green for OK, yellow for warning, red for critical. Optionally appends results to a log file. Exit code reflects the worst status found, making it suitable for cron jobs and monitoring tools.

## Usage

```bash
./disk-space-report.sh [OPTIONS]
```

## Options

| Flag | Argument | Description |
|------|----------|-------------|
| `-w` | `<percent>` | Warning threshold, % used (default: 80) |
| `-c` | `<percent>` | Critical threshold, % used (default: 90) |
| `-m` | `<mount>` | Check only this mount point (e.g. `/var`) |
| `-o` | `<file>` | Append timestamped results to this log file |
| `-h`, `--help` | | Show help and exit |

## Examples

```bash
# Check all filesystems with defaults
./disk-space-report.sh

# Custom thresholds
./disk-space-report.sh -w 75 -c 85

# Check a specific mount and log results
./disk-space-report.sh -m /var -o /var/log/disk-report.log

# Use in a cron job (exit code 2 = critical, 1 = warning, 0 = OK)
./disk-space-report.sh -o /var/log/disk-report.log || echo "Disk alert!"
```

## Notes

- Exit codes: `0` = all OK, `1` = at least one WARNING, `2` = at least one CRITICAL.
- Defaults at the top of the script can be edited to hardcode thresholds for scheduled use.
- Pseudo-filesystems (`tmpfs`, `devtmpfs`, `squashfs`, etc.) are automatically excluded.
