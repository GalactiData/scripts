#!/usr/bin/env bash
# disk-space-report.sh — Disk usage report with warning and critical thresholds.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults (edit to hardcode for scheduled/non-interactive use)
# ---------------------------------------------------------------------------
WARN_PCT=80
CRIT_PCT=90
OUTPUT_FILE=""
TARGET_MOUNT=""

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

Report disk usage across local filesystems with threshold-based status indicators.

Options:
  -w <percent>   Warning threshold, % used (default: $WARN_PCT)
  -c <percent>   Critical threshold, % used (default: $CRIT_PCT)
  -m <mount>     Check only this mount point (e.g. /)
  -o <file>      Append results to this log file
  -h, --help     Show this help

Examples:
  $(basename "$0")
  $(basename "$0") -w 75 -c 85
  $(basename "$0") -m /var -o /var/log/disk-report.log
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -w) WARN_PCT="$2";    shift 2 ;;
        -c) CRIT_PCT="$2";    shift 2 ;;
        -m) TARGET_MOUNT="$2"; shift 2 ;;
        -o) OUTPUT_FILE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# Pseudo-filesystem types to exclude
# ---------------------------------------------------------------------------
EXCLUDE_TYPES="tmpfs,devtmpfs,sysfs,proc,cgroup,cgroup2,overlay,squashfs,devpts,hugetlbfs,mqueue,pstore,securityfs,debugfs,tracefs,bpf,fusectl,efivarfs"

# ---------------------------------------------------------------------------
# Collect data
# ---------------------------------------------------------------------------
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname -f 2>/dev/null || hostname)

header="  $(printf '%-30s %-15s %10s %10s %10s %8s  %s' 'Filesystem' 'Mount' 'Total' 'Used' 'Free' 'Use%' 'Status')"
divider="  $(printf '%.0s─' {1..90})"

echo ""
echo -e "${CYAN}  Disk Space Report — $HOSTNAME — $TIMESTAMP${RESET}"
echo -e "${CYAN}  Thresholds: Warning ≥${WARN_PCT}%  Critical ≥${CRIT_PCT}%${RESET}"
echo "$divider"
echo "$header"
echo "$divider"

warn_count=0
crit_count=0
total_count=0
LOG_LINES=()

# Read df output (exclude pseudo-filesystems)
while IFS= read -r line; do
    fs=$(echo "$line"    | awk '{print $1}')
    total=$(echo "$line" | awk '{print $2}')
    used=$(echo "$line"  | awk '{print $3}')
    free=$(echo "$line"  | awk '{print $4}')
    pct=$(echo "$line"   | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $6}')

    # Skip excluded types
    fstype=$(findmnt -n -o FSTYPE "$mount" 2>/dev/null || echo "")
    if echo "$EXCLUDE_TYPES" | grep -qw "$fstype"; then continue; fi

    # Apply mount filter if specified
    if [[ -n "$TARGET_MOUNT" && "$mount" != "$TARGET_MOUNT" ]]; then continue; fi

    # Determine status
    if (( pct >= CRIT_PCT )); then
        status="CRITICAL"
        color="$RED"
        (( crit_count++ )) || true
    elif (( pct >= WARN_PCT )); then
        status="WARNING"
        color="$YELLOW"
        (( warn_count++ )) || true
    else
        status="OK"
        color="$GREEN"
    fi
    (( total_count++ )) || true

    row="$(printf '  %-30s %-15s %10s %10s %10s %7s%%  %s' "$fs" "$mount" "$total" "$used" "$free" "$pct" "$status")"
    echo -e "${color}${row}${RESET}"
    LOG_LINES+=("[$TIMESTAMP] $fs $mount ${pct}% $status")

done < <(df -h --output=source,size,used,avail,pcent,target 2>/dev/null | tail -n +2)

echo "$divider"
echo -e "  Total: ${total_count}  |  ${YELLOW}Warning: ${warn_count}${RESET}  |  ${RED}Critical: ${crit_count}${RESET}"
echo ""

# ---------------------------------------------------------------------------
# Write to log file if specified
# ---------------------------------------------------------------------------
if [[ -n "$OUTPUT_FILE" ]]; then
    for line in "${LOG_LINES[@]}"; do
        echo "$line" >> "$OUTPUT_FILE"
    done
    echo "Results appended to: $OUTPUT_FILE"
fi

# Exit with non-zero if any critical filesystems found
(( crit_count > 0 )) && exit 2
(( warn_count > 0 )) && exit 1
exit 0
