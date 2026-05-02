#Requires -Version 5.1
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Finds inactive Active Directory user and/or computer accounts.

.DESCRIPTION
    Queries Active Directory for accounts that have not logged in within a configurable
    number of days. Can report only, disable the accounts, or move them to a target OU.
    Supports exclusion lists by account name or OU path.

.PARAMETER DaysInactive
    Accounts with no login activity in this many days are considered stale. Default: 90.

.PARAMETER AccountType
    Which account types to check: User, Computer, or Both. Default: Both.

.PARAMETER Action
    What to do with stale accounts: Report (list only), Disable, or Move. Default: Report.

.PARAMETER MoveToOU
    Distinguished name of the OU to move stale accounts to. Required when Action is Move.

.PARAMETER ExcludeOU
    One or more OU distinguished names. Accounts in these OUs are skipped.

.PARAMETER ExcludeAccount
    One or more SamAccountNames to always exclude from results.

.PARAMETER OutputPath
    Export results to this CSV file path.

.PARAMETER SearchBase
    Limit the search to this OU distinguished name.

.EXAMPLE
    .\Get-StaleAccounts.ps1

.EXAMPLE
    .\Get-StaleAccounts.ps1 -DaysInactive 60 -AccountType User

.EXAMPLE
    .\Get-StaleAccounts.ps1 -Action Disable -ExcludeAccount "svc-backup","svc-monitor"

.EXAMPLE
    .\Get-StaleAccounts.ps1 -Action Move -MoveToOU "OU=Disabled,DC=contoso,DC=com"

.EXAMPLE
    .\Get-StaleAccounts.ps1 -OutputPath "C:\Reports\stale-accounts.csv"
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [int]$DaysInactive = 90,
    [ValidateSet('User', 'Computer', 'Both')]
    [string]$AccountType = 'Both',
    [ValidateSet('Report', 'Disable', 'Move')]
    [string]$Action = 'Report',
    [string]$MoveToOU,
    [string[]]$ExcludeOU,
    [string[]]$ExcludeAccount,
    [string]$OutputPath,
    [string]$SearchBase
)

$ErrorActionPreference = 'Continue'

if ($Action -eq 'Move' -and -not $MoveToOU) {
    Write-Error "-MoveToOU is required when -Action is Move."
    exit 1
}

$cutoff    = (Get-Date).AddDays(-$DaysInactive)
$adParams  = @{ Properties = 'LastLogonDate', 'DistinguishedName', 'Enabled', 'Description' }
if ($SearchBase) { $adParams.SearchBase = $SearchBase }

$stale = [System.Collections.Generic.List[PSCustomObject]]::new()

function Test-Excluded {
    param([string]$DN, [string]$Sam)
    if ($ExcludeAccount -and $ExcludeAccount -contains $Sam) { return $true }
    if ($ExcludeOU) {
        foreach ($ou in $ExcludeOU) {
            if ($DN -like "*,$ou") { return $true }
        }
    }
    return $false
}

function Get-StaleUsers {
    $filter = { Enabled -eq $true -and (LastLogonDate -lt $cutoff -or -not $LastLogonDate) }
    Get-ADUser -Filter $filter @adParams | ForEach-Object {
        if (-not (Test-Excluded -DN $_.DistinguishedName -Sam $_.SamAccountName)) {
            [PSCustomObject]@{
                Type          = 'User'
                Name          = $_.Name
                SamAccount    = $_.SamAccountName
                LastLogon     = if ($_.LastLogonDate) { $_.LastLogonDate.ToString('yyyy-MM-dd') } else { 'Never' }
                DaysSinceLogon = if ($_.LastLogonDate) { [int]((Get-Date) - $_.LastLogonDate).TotalDays } else { 9999 }
                Enabled       = $_.Enabled
                Description   = $_.Description
                DN            = $_.DistinguishedName
            }
        }
    }
}

function Get-StaleComputers {
    $filter = { Enabled -eq $true -and (LastLogonDate -lt $cutoff -or -not $LastLogonDate) }
    Get-ADComputer -Filter $filter @adParams | ForEach-Object {
        if (-not (Test-Excluded -DN $_.DistinguishedName -Sam $_.SamAccountName)) {
            [PSCustomObject]@{
                Type           = 'Computer'
                Name           = $_.Name
                SamAccount     = $_.SamAccountName
                LastLogon      = if ($_.LastLogonDate) { $_.LastLogonDate.ToString('yyyy-MM-dd') } else { 'Never' }
                DaysSinceLogon = if ($_.LastLogonDate) { [int]((Get-Date) - $_.LastLogonDate).TotalDays } else { 9999 }
                Enabled        = $_.Enabled
                Description    = $_.Description
                DN             = $_.DistinguishedName
            }
        }
    }
}

Write-Host ""
Write-Host "  Get-StaleAccounts.ps1  |  Inactive > $DaysInactive days  |  Type: $AccountType  |  Action: $Action" -ForegroundColor Cyan
Write-Host "  Querying Active Directory..." -ForegroundColor Cyan

if ($AccountType -in 'User', 'Both')     { $stale.AddRange(@(Get-StaleUsers)) }
if ($AccountType -in 'Computer', 'Both') { $stale.AddRange(@(Get-StaleComputers)) }

$sorted = $stale | Sort-Object DaysSinceLogon -Descending

if ($sorted.Count -eq 0) {
    Write-Host "`n  No stale accounts found.`n" -ForegroundColor Green
    exit 0
}

Write-Host ""
$sorted | Format-Table -AutoSize -Property Type, Name, SamAccount, LastLogon, DaysSinceLogon, Description

Write-Host "  Found: $($sorted.Count) stale account(s)"

if ($Action -ne 'Report') {
    Write-Host ""
    $actionWord = if ($Action -eq 'Disable') { 'Disabling' } else { "Moving to $MoveToOU" }
    Write-Host "  $actionWord $($sorted.Count) account(s)..." -ForegroundColor Yellow

    $success = 0
    $failed  = 0
    foreach ($acct in $sorted) {
        try {
            if ($Action -eq 'Disable') {
                if ($acct.Type -eq 'User') {
                    Disable-ADAccount -Identity $acct.DN
                } else {
                    Disable-ADAccount -Identity $acct.DN
                }
            } elseif ($Action -eq 'Move') {
                Move-ADObject -Identity $acct.DN -TargetPath $MoveToOU
            }
            $success++
        } catch {
            Write-Warning "Failed to $Action '$($acct.Name)': $_"
            $failed++
        }
    }
    Write-Host "  Done. Success: $success  |  Failed: $failed`n"
}

if ($OutputPath) {
    $sorted | Select-Object Type, Name, SamAccount, LastLogon, DaysSinceLogon, Enabled, Description, DN |
        Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Host "  Results saved: $OutputPath" -ForegroundColor Green
}

Write-Host ""
