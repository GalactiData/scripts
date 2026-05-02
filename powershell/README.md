# PowerShell Scripts

PowerShell scripts for Windows and cross-platform environments.

## Scripts

| Script | Description |
|--------|-------------|
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
