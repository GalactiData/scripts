#!/usr/bin/env bash
# patch-report.sh — Report pending updates, security updates, and reboot-required status.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults (edit to hardcode for scheduled/non-interactive use)
# ---------------------------------------------------------------------------
OUTPUT_FILE=""
REFRESH=false

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Report pending package updates, pending security updates, and whether a
reboot is required. Supports apt (Debian/Ubuntu) and dnf/yum (RHEL/Fedora).

Options:
  -u           Refresh package metadata first (requires root)
  -o <file>    Append results to this log file
  -h, --help   Show this help

Exit codes:
  0 = up to date, no reboot needed
  1 = updates available
  2 = security updates available or reboot required

Examples:
  $(basename "$0")
  sudo $(basename "$0") -u
  $(basename "$0") -o /var/log/patch-report.log
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -u) REFRESH=true;     shift ;;
        -o) OUTPUT_FILE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
if [[ -n "$OUTPUT_FILE" ]] && ! touch "$OUTPUT_FILE" 2>/dev/null; then
    echo "Cannot write to output file: $OUTPUT_FILE" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Detect package manager
# ---------------------------------------------------------------------------
if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
elif command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
else
    echo "No supported package manager found (apt-get, dnf, or yum required)." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Refresh metadata if requested
# ---------------------------------------------------------------------------
if [[ "$REFRESH" == true ]]; then
    if [[ $EUID -ne 0 ]]; then
        echo "-u (refresh metadata) requires root. Re-run with sudo." >&2
        exit 1
    fi
    echo "Refreshing package metadata..."
    case "$PKG_MGR" in
        apt)     apt-get update -qq ;;
        dnf|yum) "$PKG_MGR" -q makecache >/dev/null ;;
    esac
fi

# ---------------------------------------------------------------------------
# Collect data
# ---------------------------------------------------------------------------
UPDATES=0
SECURITY=0
REBOOT_REQUIRED=false
REBOOT_DETAIL=""
LAST_UPDATE="unknown"

# Count package lines in `dnf/yum check-update` output (pkg.arch  version  repo)
count_pkg_lines() {
    printf '%s\n' "$1" | awk '$1 ~ /\./ && NF >= 3 { c++ } END { print c + 0 }'
}

case "$PKG_MGR" in
    apt)
        # Simulated upgrade lists one "Inst" line per pending package
        sim=$(apt-get -s upgrade 2>/dev/null || true)
        UPDATES=$(printf '%s\n' "$sim" | grep -c '^Inst ' || true)
        SECURITY=$(printf '%s\n' "$sim" | grep '^Inst ' | grep -c -- '-security' || true)

        # Last recorded apt transaction
        if [[ -r /var/log/apt/history.log ]]; then
            last_line=$(grep '^Start-Date:' /var/log/apt/history.log 2>/dev/null | tail -1 || true)
            [[ -n "$last_line" ]] && LAST_UPDATE="${last_line#Start-Date: }"
        fi

        if [[ -f /var/run/reboot-required ]]; then
            REBOOT_REQUIRED=true
            if [[ -r /var/run/reboot-required.pkgs ]]; then
                pkg_count=$(sort -u /var/run/reboot-required.pkgs | wc -l)
                REBOOT_DETAIL="$pkg_count package(s) require it"
            fi
        fi
        ;;
    dnf|yum)
        # check-update exits 100 when updates are available
        raw=$("$PKG_MGR" -q check-update 2>/dev/null || true)
        UPDATES=$(count_pkg_lines "$raw")

        raw_sec=$("$PKG_MGR" -q check-update --security 2>/dev/null || true)
        SECURITY=$(count_pkg_lines "$raw_sec")

        # Most recently installed/updated package
        last_line=$(rpm -qa --last 2>/dev/null | head -1 || true)
        [[ -n "$last_line" ]] && LAST_UPDATE=$(printf '%s\n' "$last_line" | awk '{ $1=""; sub(/^ /,""); print }')

        # needs-restarting -r exits non-zero when a reboot is required
        if command -v needs-restarting &>/dev/null; then
            if ! needs-restarting -r >/dev/null 2>&1; then
                REBOOT_REQUIRED=true
            fi
        fi
        ;;
esac

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname -f 2>/dev/null || hostname)

if (( SECURITY > 0 )) || [[ "$REBOOT_REQUIRED" == true ]]; then
    STATUS="CRITICAL"
    STATUS_COLOR="$RED"
elif (( UPDATES > 0 )); then
    STATUS="UPDATES AVAILABLE"
    STATUS_COLOR="$YELLOW"
else
    STATUS="UP TO DATE"
    STATUS_COLOR="$GREEN"
fi

reboot_label="No"
if [[ "$REBOOT_REQUIRED" == true ]]; then
    reboot_label="YES"
    [[ -n "$REBOOT_DETAIL" ]] && reboot_label="YES ($REBOOT_DETAIL)"
fi

echo ""
echo -e "${CYAN}  Patch Report — $HOSTNAME — $TIMESTAMP${RESET}"
echo "  $(printf '%.0s─' {1..60})"
printf '  %-24s %s\n' "Package manager"   "$PKG_MGR"
printf '  %-24s %s\n' "Pending updates"   "$UPDATES"
printf '  %-24s %s\n' "Security updates"  "$SECURITY"
printf '  %-24s %s\n' "Reboot required"   "$reboot_label"
printf '  %-24s %s\n' "Last update run"   "$LAST_UPDATE"
echo "  $(printf '%.0s─' {1..60})"
echo -e "  Status: ${STATUS_COLOR}${STATUS}${RESET}"
if [[ "$REFRESH" != true ]]; then
    echo "  Note: counts reflect cached metadata. Run with -u to refresh first."
fi
echo ""

if [[ -n "$OUTPUT_FILE" ]]; then
    echo "[$TIMESTAMP] host=$HOSTNAME mgr=$PKG_MGR updates=$UPDATES security=$SECURITY reboot=$REBOOT_REQUIRED status=$STATUS" >> "$OUTPUT_FILE"
    echo "Results appended to: $OUTPUT_FILE"
fi

if [[ "$STATUS" == "CRITICAL" ]]; then
    exit 2
elif (( UPDATES > 0 )); then
    exit 1
fi
exit 0
