# PowerShell Scripts

PowerShell scripts for Windows and cross-platform environments.

## Scripts

| Script | Description |
|--------|-------------|
| [Clear-PrintQueue](Clear-PrintQueue/) | Clears stuck Windows print jobs by stopping the Spooler, purging the spool directory, and restarting |
| [Disable-DepartedUser](Disable-DepartedUser/) | Offboards a departed AD user: disable, password reset, group removal, and move to a disabled OU with audit trail |
| [Get-DiskSpaceReport](Get-DiskSpaceReport/) | Disk usage report across local drives with warning/critical thresholds and CSV export |
| [Get-ExpiringPasswords](Get-ExpiringPasswords/) | Reports AD accounts with passwords expiring within a configurable number of days |
| [Get-PatchStatus](Get-PatchStatus/) | Windows patch status: last update age, pending updates, and pending-reboot detection with exit codes |
| [Get-StaleAccounts](Get-StaleAccounts/) | Finds inactive AD user/computer accounts with options to report, disable, or move them |
| [Get-SystemInventory](Get-SystemInventory/) | Full hardware, OS, network, and software inventory with Console, CSV, and HTML output |
| [Invoke-TempCleanup](Invoke-TempCleanup/) | Cleans temp files, browser caches, and Windows Update cache with space-freed reporting |
| [Remove-AutodeskAEC](Remove-AutodeskAEC/) | Completely removes Autodesk AEC Collection products including registry, files, and licensing |

---

## README Template

When adding a new script, create `powershell/<script-name>/README.md` using this structure:

```markdown
# script-name.ps1

One-line description of what the script does.

## What It Does

Short paragraph explaining the problem it solves and how it works.

## Usage

\`\`\`powershell
.\script-name.ps1 [options]
\`\`\`

## Options

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Help` | Switch | Show help and exit |

## Examples

\`\`\`powershell
# Example 1 description
.\script-name.ps1 -Param value

# Example 2 description
.\script-name.ps1 -OtherParam
\`\`\`
```
