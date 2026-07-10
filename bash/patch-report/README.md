# patch-report.sh

Reports pending package updates, pending security updates, and whether a reboot is required. Exit codes for monitoring pipelines.

## What It Does

Detects the system package manager (apt on Debian/Ubuntu, dnf/yum on RHEL/Fedora) and reports how many updates are pending, how many of those are security updates, whether the machine needs a reboot (`/var/run/reboot-required` on Debian/Ubuntu, `needs-restarting -r` on RHEL), and when packages were last updated. Suitable for cron-based patch compliance monitoring or a quick check before maintenance windows.

## Usage

```bash
./patch-report.sh [OPTIONS]
```

No root required for reporting. Root is only needed with `-u`.

## Options

| Flag | Argument | Description |
|------|----------|-------------|
| `-u` | | Refresh package metadata first (`apt-get update` / `dnf makecache`, requires root) |
| `-o` | `<file>` | Append a timestamped summary line to this log file |
| `-h`, `--help` | | Show help and exit |

## Examples

```bash
# Quick report from cached metadata
./patch-report.sh

# Refresh metadata first for accurate counts
sudo ./patch-report.sh -u

# Log results for cron use
./patch-report.sh -o /var/log/patch-report.log
```

## Notes

- Exit codes: `0` = up to date and no reboot needed, `1` = updates available, `2` = security updates available or reboot required.
- Without `-u`, counts reflect the last metadata refresh and may be stale.
- Security update detection: apt matches packages from `-security` repositories; dnf/yum uses `check-update --security`.
- On RHEL-family systems, reboot detection requires `needs-restarting` (package `yum-utils` / `dnf-utils`); without it, reboot status is reported as No.
