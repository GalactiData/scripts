#Requires -Version 5.1
#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Offboards a departed user's Active Directory account safely and with an audit trail.

.DESCRIPTION
    Runs the standard offboarding steps against a single AD user account:

      1. Records current group memberships (to the log and optional CSV) BEFORE any change
      2. Disables the account
      3. Resets the password to a long random value
      4. Removes the account from all groups (except its primary group)
      5. Stamps the description with the offboard date, preserving the old description
      6. Moves the account to a disabled/offboarded OU (runs last — moving changes the DN)

    Every step is logged. Supports -WhatIf to preview all changes without touching AD.

.PARAMETER Identity
    SamAccountName of the user to offboard.

.PARAMETER DisabledOU
    Distinguished name of the OU to move the account to (e.g. "OU=Disabled,DC=contoso,DC=com").
    If omitted, the account is not moved.

.PARAMETER SkipPasswordReset
    Do not reset the account password.

.PARAMETER SkipGroupRemoval
    Do not remove group memberships (they are still recorded).

.PARAMETER OutputPath
    Export an audit CSV of every action taken (including the removed groups) to this path.

.PARAMETER Force
    Skip the confirmation prompt.

.PARAMETER LogPath
    Write a log to this file. Defaults to a timestamped file in $env:TEMP.

.EXAMPLE
    .\Disable-DepartedUser.ps1 -Identity jsmith -WhatIf

.EXAMPLE
    .\Disable-DepartedUser.ps1 -Identity jsmith -DisabledOU "OU=Disabled,DC=contoso,DC=com"

.EXAMPLE
    .\Disable-DepartedUser.ps1 -Identity jsmith -SkipGroupRemoval -OutputPath "C:\Reports\jsmith-offboard.csv"
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string]$Identity,
    [string]$DisabledOU,
    [switch]$SkipPasswordReset,
    [switch]$SkipGroupRemoval,
    [string]$OutputPath,
    [switch]$Force,
    [string]$LogPath
)

# ===========================================================================
# CONFIGURATION — edit to set persistent defaults
# ===========================================================================
$Config = @{
    DisabledOU = ''       # Target OU distinguished name, or '' to leave in place
    Force      = $false
    LogPath    = ''
}
# ===========================================================================

$ErrorActionPreference = 'Continue'

# Apply config defaults
if (-not $PSBoundParameters.ContainsKey('DisabledOU') -and $Config.DisabledOU) { $DisabledOU = $Config.DisabledOU }
if (-not $PSBoundParameters.ContainsKey('Force')      -and $Config.Force)      { $Force      = [switch]$true }
if (-not $PSBoundParameters.ContainsKey('LogPath')    -and $Config.LogPath)    { $LogPath    = $Config.LogPath }

if (-not $LogPath) {
    $ts      = Get-Date -Format 'yyyyMMdd_HHmmss'
    $LogPath = Join-Path $env:TEMP "Disable-DepartedUser_$ts.log"
}
$null = New-Item -ItemType File -Path $LogPath -Force

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    if ($Level -eq 'WARN') { Write-Warning $Message }
    else                   { Write-Host "  $Message" }
}

# Audit rows: one per action, exported to -OutputPath at the end
$audit = [System.Collections.Generic.List[PSCustomObject]]::new()
function Add-Audit {
    param([string]$Step, [string]$Detail, [string]$Result)
    $audit.Add([PSCustomObject]@{
        Timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        User      = $Identity
        Step      = $Step
        Detail    = $Detail
        Result    = $Result
    })
}

function New-RandomSecurePassword {
    param([int]$Length = 24)
    # Built directly as a SecureString — the full password never exists in plain text
    $pool = 48..57 + 65..90 + 97..122 + @(33, 35, 36, 37, 38, 42, 43, 64)
    $secure = [System.Security.SecureString]::new()
    for ($i = 0; $i -lt $Length; $i++) {
        $secure.AppendChar([char]($pool | Get-Random))
    }
    $secure
}

Write-Host ""
Write-Host "  Disable-DepartedUser.ps1" -ForegroundColor Cyan
Write-Host "  Log: $LogPath"
Write-Host ""

# ---------------------------------------------------------------------------
# Look up the user and validate the target OU before changing anything
# ---------------------------------------------------------------------------
try {
    $user = Get-ADUser -Identity $Identity -Properties MemberOf, Description, Enabled, DisplayName -ErrorAction Stop
} catch {
    Write-Log "User '$Identity' not found in Active Directory." -Level 'WARN'
    exit 1
}

if ($DisabledOU) {
    try {
        $null = Get-ADObject -Identity $DisabledOU -ErrorAction Stop
    } catch {
        Write-Log "Target OU not found: $DisabledOU" -Level 'WARN'
        exit 1
    }
}

$groups = @($user.MemberOf)

Write-Host "  User        : $($user.DisplayName) ($($user.SamAccountName))"
Write-Host "  Enabled     : $($user.Enabled)"
Write-Host "  Groups      : $($groups.Count) (primary group is kept automatically)"
Write-Host "  Description : $($user.Description)"
Write-Host ""
Write-Host "  Planned steps:" -ForegroundColor Yellow
Write-Host "    - Record group memberships"
Write-Host "    - Disable account"
if (-not $SkipPasswordReset) { Write-Host "    - Reset password to a random value" }
if (-not $SkipGroupRemoval)  { Write-Host "    - Remove $($groups.Count) group membership(s)" }
Write-Host "    - Stamp description with offboard date"
if ($DisabledOU) { Write-Host "    - Move account to: $DisabledOU" }
Write-Host ""

if (-not $Force -and -not $WhatIfPreference) {
    $answer = Read-Host "  Type YES to offboard this account or anything else to abort"
    if ($answer -ne 'YES') {
        Write-Host "  Aborted. No changes made.`n" -ForegroundColor Green
        exit 0
    }
}

Write-Log "Offboarding started for '$($user.SamAccountName)' (WhatIf=$WhatIfPreference)"
$failed = 0

# ---------------------------------------------------------------------------
# Step 1: Record group memberships BEFORE any change (audit/undo trail)
# ---------------------------------------------------------------------------
if ($groups.Count -gt 0) {
    Write-Log "Recording $($groups.Count) group membership(s):"
    foreach ($g in $groups) {
        Write-Log "  Member of: $g"
        Add-Audit -Step 'RecordGroup' -Detail $g -Result 'Recorded'
    }
} else {
    Write-Log "No group memberships beyond the primary group."
}

# ---------------------------------------------------------------------------
# Step 2: Disable the account
# ---------------------------------------------------------------------------
if ($PSCmdlet.ShouldProcess($user.SamAccountName, 'Disable account')) {
    try {
        Disable-ADAccount -Identity $user.DistinguishedName -ErrorAction Stop
        Write-Log "Account disabled."
        Add-Audit -Step 'Disable' -Detail $user.DistinguishedName -Result 'Success'
    } catch {
        Write-Log "Failed to disable account: $_" -Level 'WARN'
        Add-Audit -Step 'Disable' -Detail $user.DistinguishedName -Result "Failed: $_"
        $failed++
    }
}

# ---------------------------------------------------------------------------
# Step 3: Reset the password
# ---------------------------------------------------------------------------
if (-not $SkipPasswordReset) {
    if ($PSCmdlet.ShouldProcess($user.SamAccountName, 'Reset password to a random value')) {
        try {
            Set-ADAccountPassword -Identity $user.DistinguishedName -Reset `
                -NewPassword (New-RandomSecurePassword) -ErrorAction Stop
            Write-Log "Password reset to a random value (not recorded anywhere)."
            Add-Audit -Step 'PasswordReset' -Detail 'Random 24-character password' -Result 'Success'
        } catch {
            Write-Log "Failed to reset password: $_" -Level 'WARN'
            Add-Audit -Step 'PasswordReset' -Detail '' -Result "Failed: $_"
            $failed++
        }
    }
}

# ---------------------------------------------------------------------------
# Step 4: Remove group memberships (primary group is not in MemberOf)
# ---------------------------------------------------------------------------
if (-not $SkipGroupRemoval -and $groups.Count -gt 0) {
    foreach ($g in $groups) {
        if ($PSCmdlet.ShouldProcess($user.SamAccountName, "Remove from group: $g")) {
            try {
                Remove-ADGroupMember -Identity $g -Members $user.DistinguishedName -Confirm:$false -ErrorAction Stop
                Write-Log "Removed from group: $g"
                Add-Audit -Step 'RemoveGroup' -Detail $g -Result 'Success'
            } catch {
                Write-Log "Failed to remove from '$g': $_" -Level 'WARN'
                Add-Audit -Step 'RemoveGroup' -Detail $g -Result "Failed: $_"
                $failed++
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Step 5: Stamp the description (preserve the old one)
# ---------------------------------------------------------------------------
$stamp   = "Offboarded $(Get-Date -Format 'yyyy-MM-dd')"
$newDesc = if ($user.Description) { "$stamp | was: $($user.Description)" } else { $stamp }

if ($PSCmdlet.ShouldProcess($user.SamAccountName, "Set description: $newDesc")) {
    try {
        Set-ADUser -Identity $user.DistinguishedName -Description $newDesc -ErrorAction Stop
        Write-Log "Description set: $newDesc"
        Add-Audit -Step 'Description' -Detail $newDesc -Result 'Success'
    } catch {
        Write-Log "Failed to set description: $_" -Level 'WARN'
        Add-Audit -Step 'Description' -Detail $newDesc -Result "Failed: $_"
        $failed++
    }
}

# ---------------------------------------------------------------------------
# Step 6: Move to the disabled OU — LAST, because moving changes the DN
# ---------------------------------------------------------------------------
if ($DisabledOU) {
    if ($PSCmdlet.ShouldProcess($user.SamAccountName, "Move to OU: $DisabledOU")) {
        try {
            Move-ADObject -Identity $user.DistinguishedName -TargetPath $DisabledOU -ErrorAction Stop
            Write-Log "Moved to: $DisabledOU"
            Add-Audit -Step 'Move' -Detail $DisabledOU -Result 'Success'
        } catch {
            Write-Log "Failed to move account: $_" -Level 'WARN'
            Add-Audit -Step 'Move' -Detail $DisabledOU -Result "Failed: $_"
            $failed++
        }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$modeLabel = if ($WhatIfPreference) { ' (WhatIf — no changes made)' } else { '' }
Write-Host ""
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  SUMMARY$modeLabel"
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  User            : $($user.SamAccountName)"
Write-Host "  Groups recorded : $($groups.Count)"
Write-Host "  Failed steps    : $failed"
Write-Host "  Log             : $LogPath"
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

if ($OutputPath -and $audit.Count -gt 0) {
    $audit | Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Host "  Audit CSV saved: $OutputPath" -ForegroundColor Green
    Write-Host ""
}

Write-Log "Offboarding complete. FailedSteps=$failed"
if ($failed -gt 0) { exit 1 }
exit 0
