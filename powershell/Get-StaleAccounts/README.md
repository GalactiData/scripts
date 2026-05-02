# Get-StaleAccounts.ps1

Finds Active Directory user and/or computer accounts that haven't logged in within a configurable number of days. Can report only, disable the accounts, or move them to a specified OU.

## What It Does

Queries Active Directory for enabled accounts whose last logon date is older than the inactivity threshold (or accounts that have never logged in). Supports exclusion by account name or OU path to protect service accounts and system accounts. Useful for regular AD hygiene to reduce attack surface and reclaim licenses.

## Usage

```powershell
.\Get-StaleAccounts.ps1 [[-DaysInactive] <int>] [[-AccountType] <User|Computer|Both>]
                        [[-Action] <Report|Disable|Move>] [[-MoveToOU] <dn>]
                        [[-ExcludeOU] <dn[]>] [[-ExcludeAccount] <string[]>]
                        [[-SearchBase] <dn>] [[-OutputPath] <path>]
```

Requires the **ActiveDirectory** PowerShell module (RSAT).

## Options

| Parameter | Type | Description |
|-----------|------|-------------|
| `-DaysInactive` | Int | Inactivity threshold in days (default: 90) |
| `-AccountType` | String | `User`, `Computer`, or `Both` (default: Both) |
| `-Action` | String | `Report` (default), `Disable`, or `Move` |
| `-MoveToOU` | String | Target OU distinguished name — required when `-Action` is `Move` |
| `-ExcludeOU` | String[] | Skip accounts in these OUs (distinguished names) |
| `-ExcludeAccount` | String[] | Skip these SamAccountNames |
| `-SearchBase` | String | Limit search to this OU |
| `-OutputPath` | String | Export results to this CSV file |

## Examples

```powershell
# Report all accounts inactive for 90+ days
.\Get-StaleAccounts.ps1

# Report user accounts only, inactive 60+ days
.\Get-StaleAccounts.ps1 -DaysInactive 60 -AccountType User

# Disable stale accounts, excluding service accounts
.\Get-StaleAccounts.ps1 -Action Disable -ExcludeAccount "svc-backup", "svc-monitor"

# Move stale accounts to a disabled OU
.\Get-StaleAccounts.ps1 -Action Move -MoveToOU "OU=Disabled,DC=contoso,DC=com"

# Report and save to CSV
.\Get-StaleAccounts.ps1 -OutputPath "C:\Reports\stale-accounts.csv"
```
