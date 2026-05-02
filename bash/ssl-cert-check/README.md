# ssl-cert-check.sh

Checks SSL/TLS certificate expiry for a list of domains and flags any expiring within a configurable warning window. Color-coded output with exit codes for monitoring pipelines.

## What It Does

Connects to each domain via `openssl s_client`, retrieves the certificate, and parses the expiry date. Status is color-coded: green for OK, yellow for expiring soon, red for expired. Domains that are unreachable are flagged separately. Suitable for cron-based monitoring or ad-hoc checks before renewals lapse.

## Usage

```bash
./ssl-cert-check.sh [OPTIONS] [domain1 domain2 ...]
```

Requires `openssl`.

## Options

| Flag | Argument | Description |
|------|----------|-------------|
| `-f` | `<file>` | File with one domain per line (lines starting with `#` are ignored) |
| `-d` | `<days>` | Warning threshold in days (default: 30) |
| `-p` | `<port>` | Port to connect on (default: 443) |
| `-o` | `<file>` | Append timestamped results to this log file |
| `-t` | `<secs>` | Connection timeout in seconds (default: 10) |
| `-h`, `--help` | | Show help and exit |

## Examples

```bash
# Check a few domains
./ssl-cert-check.sh example.com google.com

# Check from a file with a 60-day warning window
./ssl-cert-check.sh -f /etc/ssl-domains.txt -d 60

# Log results for cron use
./ssl-cert-check.sh -f /etc/ssl-domains.txt -o /var/log/ssl-check.log

# Non-standard port
./ssl-cert-check.sh -p 8443 internal.example.com
```

## Notes

- Exit codes: `0` = all OK, `1` = at least one WARNING, `2` = at least one EXPIRED.
- Domain file supports inline `#` comments and blank lines.
- Default threshold and port can be edited at the top of the script for scheduled use.
