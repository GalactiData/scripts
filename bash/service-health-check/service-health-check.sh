#!/usr/bin/env bash
# service-health-check.sh — Check Linux service status and optionally restart stopped services.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults (edit to hardcode for scheduled/non-interactive use)
# ---------------------------------------------------------------------------
SERVICE_FILE=""
AUTO_RESTART=false
LOG_FILE=""

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
Usage: $(basename "$0") [OPTIONS] [service1 service2 ...]

Check the status of one or more systemd services and optionally restart stopped ones.

Options:
  -f <file>    File containing one service name per line
  -r           Auto-restart services that are not running
  -l <file>    Append all state changes and results to this log file
  -h, --help   Show this help

Services can be passed as arguments (with or without -f).

Examples:
  $(basename "$0") nginx ssh postgresql
  $(basename "$0") -f /etc/monitored-services.txt -r
  $(basename "$0") -r -l /var/log/service-health.log nginx mysql
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SERVICES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f) SERVICE_FILE="$2"; shift 2 ;;
        -r) AUTO_RESTART=true; shift ;;
        -l) LOG_FILE="$2";     shift 2 ;;
        -h|--help) usage ;;
        -*) echo "Unknown option: $1" >&2; usage ;;
        *)  SERVICES+=("$1"); shift ;;
    esac
done

# Load services from file
if [[ -n "$SERVICE_FILE" ]]; then
    if [[ ! -r "$SERVICE_FILE" ]]; then
        echo "Cannot read service file: $SERVICE_FILE" >&2
        exit 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line// /}"
        [[ -n "$line" ]] && SERVICES+=("$line")
    done < "$SERVICE_FILE"
fi

if [[ ${#SERVICES[@]} -eq 0 ]]; then
    echo "No services specified. Use -f <file> or pass service names as arguments." >&2
    usage
fi

# Validate log file is writable before doing any work
if [[ -n "$LOG_FILE" ]] && ! touch "$LOG_FILE" 2>/dev/null; then
    echo "Cannot write to log file: $LOG_FILE" >&2
    exit 1
fi

# Require systemctl
if ! command -v systemctl &>/dev/null; then
    echo "systemctl is required but not found. This script requires a systemd-based system." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
# if-form (not `[[ ]] &&`) so the function returns 0 when no log file is set;
# otherwise `set -e` would abort the script on every log call.
log() {
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    fi
}

# ---------------------------------------------------------------------------
# Check a single service
# Result is written to global _svc_result; output printed directly (no subshell).
# ---------------------------------------------------------------------------
_svc_result=""

check_service() {
    local svc="$1"
    local action="none"
    local color label

    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        color="$GREEN"
        label="RUNNING"
    else
        local raw_status
        raw_status=$(systemctl is-active "$svc" 2>/dev/null || true)
        color="$RED"
        label="STOPPED (${raw_status:-unknown})"

        if [[ "$AUTO_RESTART" == true ]]; then
            if systemctl restart "$svc" 2>/dev/null; then
                sleep 2
                if systemctl is-active --quiet "$svc" 2>/dev/null; then
                    color="$YELLOW"
                    label="RESTARTED"
                    action="restarted"
                else
                    label="RESTART FAILED"
                    action="restart_failed"
                fi
            else
                label="RESTART FAILED"
                action="restart_failed"
            fi
        fi
    fi

    printf "${color}  %-16s${RESET}  %s\n" "$label" "$svc"
    log "$svc label=$label action=$action"
    _svc_result="$label"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname -f 2>/dev/null || hostname)

echo ""
printf "${CYAN}  Service Health Check — %s — %s${RESET}\n" "$HOSTNAME" "$TIMESTAMP"
[[ "$AUTO_RESTART" == true ]] && printf '%s  Auto-restart: ENABLED%s\n' "$YELLOW" "$RESET"
echo "  $(printf '%.0s─' {1..60})"
printf "  %-16s  %s\n" "STATUS" "SERVICE"
echo "  $(printf '%.0s─' {1..60})"

log "--- Service health check started on $HOSTNAME ---"

running=0
stopped=0
restarted=0
failed=0

for svc in "${SERVICES[@]}"; do
    check_service "$svc"
    case "$_svc_result" in
        RUNNING)         (( running++ ))   || true ;;
        RESTARTED)       (( restarted++ )) || true ;;
        RESTART\ FAILED) (( failed++ ))    || true ;;
        *)               (( stopped++ ))   || true ;;
    esac
done

echo "  $(printf '%.0s─' {1..60})"
printf "  Checked: %d  |  ${GREEN}Running: %d${RESET}  |  ${YELLOW}Restarted: %d${RESET}  |  ${RED}Stopped/Failed: %d${RESET}\n" \
    "${#SERVICES[@]}" "$running" "$restarted" "$(( stopped + failed ))"
[[ -n "$LOG_FILE" ]] && echo "  Log: $LOG_FILE"
echo ""

log "--- Summary: running=$running restarted=$restarted stopped=$stopped failed=$failed ---"

(( failed > 0 || stopped > 0 )) && exit 2
(( restarted > 0 ))             && exit 1
exit 0
