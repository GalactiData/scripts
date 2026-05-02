# Get-ExpiringPasswords.ps1

Reports Active Directory user accounts whose passwords will expire within a configurable number of days. Results are sorted by days remaining so the most urgent accounts appear first.

## What It Does

Queries Active Directory for enabled user accounts with expiring passwords, respecting both the domain default password policy and any fine-grained password policies applied to individual users or groups. Useful for proactive user communication before accounts lock out.

## Usage

```powershell
.\Get-ExpiringPasswords.ps1 [[-DaysWarning] <int>] [-IncludeNeverExpires]
                            [[-SearchBase] <dn>] [[-OutputPath] <path>]
```

Requires the **ActiveDirectory** PowerShell module (RSAT).

## Options

| Parameter | Type | Description |
|-----------|------|-------------|
| `-DaysWarning` | Int | Report accounts expiring within this many days (default: 14) |
| `-IncludeNeverExpires` | Switch | Include accounts flagged as "Password never expires" |
| `-SearchBase` | String | Limit search to this OU distinguished name |
| `-OutputPath` | String | Export results to this CSV file path |

## Examples

```powershell
# Default: accounts expiring in the next 14 days
.\Get-ExpiringPasswords.ps1

# Wider warning window
.\Get-ExpiringPasswords.ps1 -DaysWarning 30

# Specific OU, save to CSV
.\Get-ExpiringPasswords.ps1 -SearchBase "OU=Staff,DC=contoso,DC=com" -OutputPath "C:\Reports\expiring.csv"

# Include never-expires accounts for auditing
.\Get-ExpiringPasswords.ps1 -IncludeNeverExpires -DaysWarning 30
```
