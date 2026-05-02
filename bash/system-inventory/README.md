# system-inventory.sh

Collects a hardware and software inventory snapshot of a Linux machine and outputs it to the console or a file.

## What It Does

Gathers CPU model and core count, RAM usage, disk mounts, GPU (via `lspci`), OS and kernel version, uptime, network interfaces with IPs and MACs, and the full installed package list (supports `dpkg`/`apt`, `rpm`, and `pacman`). Useful for auditing Linux servers or workstations, generating pre-change records, or onboarding new machines.

## Usage

```bash
./system-inventory.sh [OPTIONS]
```

## Options

| Flag | Argument | Description |
|------|----------|-------------|
| `-o` | `<file>` | Write output to this file instead of stdout |
| `--format` | `text\|csv` | Output format: `text` (default) or `csv` |
| `--skip-packages` | | Skip the installed package list for a faster run |
| `-h`, `--help` | | Show help and exit |

## Examples

```bash
# Console output
./system-inventory.sh

# Save to file
./system-inventory.sh -o /tmp/inventory.txt

# CSV format
./system-inventory.sh --format csv -o /tmp/inventory.csv

# Skip package list (faster)
./system-inventory.sh --skip-packages -o /tmp/inventory.txt
```

## Notes

- Does not require `root` for most data. Serial number and some DMI fields may require elevated privileges.
- Package detection is automatic: uses `dpkg` on Debian/Ubuntu, `rpm` on RHEL/CentOS, `pacman` on Arch.
- `lspci` must be installed for GPU detection (`pciutils` package).
