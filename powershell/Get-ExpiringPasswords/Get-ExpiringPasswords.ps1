#Requires -Version 5.1
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Reports Active Directory user accounts with passwords expiring within a set number of days.

.DESCRIPTION
    Queries Active Directory for enabled user accounts whose passwords will expire within
    the specified warning window. Respects both the default domain password policy and
    any fine-grained password policies. Results are sorted by days remaining (most urgent first).

.PARAMETER DaysWarning
    Report accounts expiring within this many days. Default: 14.

.PARAMETER IncludeNeverExpires
    Include accounts flagged as "Password never expires". Excluded by default.

.PARAMETER SearchBase
    Limit the search to this OU distinguished name.

.PARAMETER OutputPath
    Export results to this CSV file path.

.EXAMPLE
    .\Get-ExpiringPasswords.ps1

.EXAMPLE
    .\Get-ExpiringPasswords.ps1 -DaysWarning 30

.EXAMPLE
    .\Get-ExpiringPasswords.ps1 -DaysWarning 7 -OutputPath "C:\Reports\expiring.csv"

.EXAMPLE
    .\Get-ExpiringPasswords.ps1 -SearchBase "OU=Staff,DC=contoso,DC=com"
#>

[CmdletBinding()]
param (
    [ValidateRange(1, 3650)]
    [int]$DaysWarning = 14,
    [switch]$IncludeNeverExpires,
    [string]$SearchBase,
    [string]$OutputPath
)

$ErrorActionPreference = 'Continue'

# Get default max password age from domain policy
$domain         = Get-ADDomain
$defaultPolicy  = Get-ADDefaultDomainPasswordPolicy
$defaultMaxAge  = $defaultPolicy.MaxPasswordAge

if (-not $defaultMaxAge -or $defaultMaxAge.TotalDays -le 0) {
    Write-Warning ("The default domain policy has no maximum password age, so passwords never expire by default. " +
                   "Only accounts covered by a fine-grained password policy will appear in this report.")
}

Write-Host ""
Write-Host "  Get-ExpiringPasswords.ps1  |  Warning window: $DaysWarning day(s)" -ForegroundColor Cyan
Write-Host "  Domain: $($domain.DNSRoot)  |  Default max password age: $($defaultMaxAge.Days) days"
Write-Host "  Querying Active Directory..." -ForegroundColor Cyan

$adParams = @{
    Filter     = { Enabled -eq $true -and PasswordNeverExpires -eq $false }
    Properties = 'PasswordLastSet', 'PasswordNeverExpires', 'PasswordExpired',
                 'msDS-UserPasswordExpiryTimeComputed', 'EmailAddress', 'DisplayName', 'Description'
}
if ($SearchBase) { $adParams.SearchBase = $SearchBase }

$now     = Get-Date
$cutoff  = $now.AddDays($DaysWarning)
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

Get-ADUser @adParams | ForEach-Object {
    $user = $_

    if (-not $IncludeNeverExpires -and $user.PasswordNeverExpires) { return }
    if (-not $user.PasswordLastSet) { return }

    # msDS-UserPasswordExpiryTimeComputed accounts for fine-grained policies
    $expiryRaw = $user.'msDS-UserPasswordExpiryTimeComputed'
    if ($expiryRaw -and $expiryRaw -ne 0 -and $expiryRaw -ne 9223372036854775807) {
        $expiry = [DateTime]::FromFileTime($expiryRaw)
    } elseif ($defaultMaxAge.Days -gt 0) {
        $expiry = $user.PasswordLastSet.Add($defaultMaxAge)
    } else {
        return  # Password never expires per policy
    }

    if ($expiry -gt $now -and $expiry -le $cutoff) {
        $daysLeft = [int]($expiry - $now).TotalDays
        $results.Add([PSCustomObject]@{
            SamAccountName = $user.SamAccountName
            DisplayName    = $user.DisplayName
            Email          = $user.EmailAddress
            PasswordLastSet = $user.PasswordLastSet.ToString('yyyy-MM-dd')
            ExpiresOn      = $expiry.ToString('yyyy-MM-dd')
            DaysRemaining  = $daysLeft
            Description    = $user.Description
        })
    }
}

$sorted = $results | Sort-Object DaysRemaining

if ($sorted.Count -eq 0) {
    Write-Host "`n  No accounts expiring within $DaysWarning day(s).`n" -ForegroundColor Green
    exit 0
}

Write-Host ""
$sorted | Format-Table -AutoSize -Property DaysRemaining, SamAccountName, DisplayName, ExpiresOn, PasswordLastSet, Email

Write-Host "  Found: $($sorted.Count) account(s) expiring within $DaysWarning day(s)"
Write-Host ""

if ($OutputPath) {
    $sorted | Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Host "  Results saved: $OutputPath" -ForegroundColor Green
    Write-Host ""
}
