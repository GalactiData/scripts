# Bash Scripts

Shell scripts for Linux/macOS environments.

## Scripts

| Script | Description |
|--------|-------------|
| [disk-space-report](disk-space-report/) | Disk usage report across local filesystems with warning/critical thresholds and exit codes |
| [docker-install](docker-install/) | Installs Docker Engine + Compose v2 plugin on Ubuntu/Debian and adds a user to the docker group |
| [service-health-check](service-health-check/) | Checks systemd service status and optionally restarts stopped services |
| [ssl-cert-check](ssl-cert-check/) | SSL/TLS certificate expiry checker for a list of domains |
| [system-inventory](system-inventory/) | Full hardware, OS, network, and package inventory snapshot for Linux machines |

---

## README Template

When adding a new script, create `bash/<script-name>/README.md` using this structure:

```markdown
# script-name.sh

One-line description of what the script does.

## What It Does

Short paragraph explaining the problem it solves and how it works.

## Usage

\`\`\`bash
./script-name.sh [options]
\`\`\`

## Options

| Flag | Argument | Description |
|------|----------|-------------|
| `-h` | | Show help and exit |

## Examples

\`\`\`bash
# Example 1 description
./script-name.sh --flag value

# Example 2 description
./script-name.sh --other-flag
\`\`\`
```
