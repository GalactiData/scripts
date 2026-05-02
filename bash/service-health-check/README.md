# service-health-check.sh

Checks the status of Linux systemd services and optionally restarts any that are stopped. Logs all state changes with timestamps.

## What It Does

Checks each service via `systemctl is-active` and reports its status with color-coded output. When auto-restart is enabled, stopped services are restarted and the result (restarted successfully or failed) is recorded. Exit codes reflect the worst status found, making the script suitable for cron jobs and monitoring integrations.

## Usage

```bash
./service-health-check.sh [OPTIONS] [service1 service2 ...]
```

Requires a `systemd`-based Linux distribution.

## Options

| Flag | Argument | Description |
|------|----------|-------------|
| `-f` | `<file>` | File with one service name per line |
| `-r` | | Enable auto-restart for stopped services |
| `-l` | `<file>` | Append timestamped state changes to this log file |
| `-h`, `--help` | | Show help and exit |

## Examples

```bash
# Check a few services
./service-health-check.sh nginx ssh postgresql

# Check from a file
./service-health-check.sh -f /etc/monitored-services.txt

# Auto-restart stopped services and log
./service-health-check.sh -r -l /var/log/service-health.log -f /etc/monitored-services.txt

# Use in cron — exit 2 if anything is stopped/failed
./service-health-check.sh -r nginx mysql || echo "Service alert on $(hostname)"
```

## Notes

- Exit codes: `0` = all running, `1` = one or more were restarted (now running), `2` = one or more stopped or restart failed.
- Service file supports `#` comments and blank lines.
- Default options can be hardcoded at the top of the script for scheduled use.
- Requires `sudo` or root when `-r` (auto-restart) is used.
