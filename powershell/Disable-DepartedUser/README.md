# Disable-DepartedUser.ps1

Offboards a departed user's Active Directory account: disable, random password reset, group removal, description stamp, and move to a disabled OU — with a full audit trail.

## What It Does

Runs the standard leaver process against a single AD account in a safe order. Group memberships are recorded to the log (and optional audit CSV) **before** anything is removed, so there is always an undo trail. The account is then disabled, its password reset to a random 24-character value (never displayed or stored), group memberships removed (the primary group — normally Domain Users — is kept automatically), the description stamped with the offboard date while preserving the old text, and finally the account is moved to a disabled OU. The move runs last because it changes the account's distinguished name.

`-WhatIf` previews every step without touching AD.

## Usage

```powershell
.\Disable-DepartedUser.ps1 -Identity <SamAccountName> [options]
```

Requires the ActiveDirectory module (RSAT) and rights to modify the target account.

## Options

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Identity` | String | SamAccountName of the user to offboard (required) |
| `-DisabledOU` | String | Distinguished name of the OU to move the account to; omit to leave in place |
| `-SkipPasswordReset` | Switch | Do not reset the password |
| `-SkipGroupRemoval` | Switch | Do not remove group memberships (still recorded) |
| `-OutputPath` | String | Export an audit CSV of every action (including removed groups) |
| `-WhatIf` | Switch | Preview all steps without making changes |
| `-Force` | Switch | Skip the confirmation prompt |
| `-LogPath` | String | Log file path (default: timestamped file in `%TEMP%`) |

## Examples

```powershell
# Preview what would happen
.\Disable-DepartedUser.ps1 -Identity jsmith -WhatIf

# Full offboard with move to a disabled OU
.\Disable-DepartedUser.ps1 -Identity jsmith -DisabledOU "OU=Disabled,DC=contoso,DC=com"

# Disable and reset only, keep groups, save the audit trail
.\Disable-DepartedUser.ps1 -Identity jsmith -SkipGroupRemoval -OutputPath "C:\Reports\jsmith-offboard.csv"
```

## Notes

- Exit codes: `0` = success (or aborted at the prompt), `1` = user/OU not found or one or more steps failed.
- Group memberships are always recorded before removal — check the log or audit CSV to restore them if needed.
- The primary group is not removed (AD does not list it in `MemberOf` and does not allow removing it).
- This handles the AD side only. Mailbox, M365 license, and sign-in session revocation are separate steps in Exchange/Entra.
- A `$Config` block at the top of the script can hardcode `DisabledOU` and other defaults for repeated use.
