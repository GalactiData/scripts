# Get-SystemInventory.ps1

Collects a full hardware and software inventory snapshot of a Windows machine and outputs it to the console, a set of CSV files, or a self-contained HTML report.

## What It Does

Gathers CPU model and core count, RAM usage, disk drives, GPU, OS details (build, uptime, last boot), active network adapters with IPs and MACs, and the full list of installed software. Useful for onboarding a new machine, generating a record before a major change, or fleet auditing.

## Usage

```powershell
.\Get-SystemInventory.ps1 [[-OutputPath] <path>] [[-Format] <Console|CSV|HTML>] [-SkipSoftware]
```

## Options

| Parameter | Type | Description |
|-----------|------|-------------|
| `-OutputPath` | String | Output file path. For CSV, used as the base name — one file per section is created alongside it. |
| `-Format` | String | `Console` (default), `CSV`, or `HTML` |
| `-SkipSoftware` | Switch | Skip the installed software list for a faster run |

## Examples

```powershell
# Console output (default)
.\Get-SystemInventory.ps1

# HTML report
.\Get-SystemInventory.ps1 -Format HTML -OutputPath "C:\Reports\inventory.html"

# CSV files (creates inventory-system.csv, inventory-disks.csv, etc.)
.\Get-SystemInventory.ps1 -Format CSV -OutputPath "C:\Reports\inventory.csv"

# Quick hardware-only snapshot
.\Get-SystemInventory.ps1 -SkipSoftware
```

## Notes

- Does not require elevated privileges for most data. Software from HKLM only; per-user installs may not appear.
- For CSV output, one file is created per section (system, cpu, memory, disks, gpu, network, software) in the same directory as `-OutputPath`.
