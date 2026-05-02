#!/usr/bin/env bash
# ssl-cert-check.sh — Check SSL/TLS certificate expiry for a list of domains.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults (edit to hardcode for scheduled/non-interactive use)
# ---------------------------------------------------------------------------
WARN_DAYS=30
DOMAIN_FILE=""
OUTPUT_FILE=""
PORT=443
TIMEOUT=10

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
Usage: $(basename "$0") [OPTIONS] [domain1 domain2 ...]

Check SSL/TLS certificate expiry for one or more domains.

Options:
  -f <file>    File containing one domain per line
  -d <days>    Warning threshold in days (default: $WARN_DAYS)
  -p <port>    Port to connect on (default: $PORT)
  -o <file>    Append results to this log file
  -t <secs>    Connection timeout in seconds (default: $TIMEOUT)
  -h, --help   Show this help

Domains can also be passed as arguments (with or without -f).

Examples:
  $(basename "$0") example.com google.com
  $(basename "$0") -f /etc/ssl-domains.txt
  $(basename "$0") -d 60 -o /var/log/ssl-check.log example.com
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
DOMAINS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f) DOMAIN_FILE="$2"; shift 2 ;;
        -d) WARN_DAYS="$2";   shift 2 ;;
        -p) PORT="$2";        shift 2 ;;
        -o) OUTPUT_FILE="$2"; shift 2 ;;
        -t) TIMEOUT="$2";     shift 2 ;;
        -h|--help) usage ;;
        -*) echo "Unknown option: $1" >&2; usage ;;
        *)  DOMAINS+=("$1"); shift ;;
    esac
done

# Load domains from file
if [[ -n "$DOMAIN_FILE" ]]; then
    if [[ ! -r "$DOMAIN_FILE" ]]; then
        echo "Cannot read domain file: $DOMAIN_FILE" >&2
        exit 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"   # strip inline comments
        line="${line// /}"   # strip spaces
        [[ -n "$line" ]] && DOMAINS+=("$line")
    done < "$DOMAIN_FILE"
fi

if [[ ${#DOMAINS[@]} -eq 0 ]]; then
    echo "No domains specified. Use -f <file> or pass domain names as arguments." >&2
    usage
fi

# Check dependency
if ! command -v openssl &>/dev/null; then
    echo "openssl is required but not installed." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Check a single domain
# ---------------------------------------------------------------------------
check_domain() {
    local domain="$1"
    local now_epoch
    now_epoch=$(date +%s)

    # Fetch certificate
    local cert_info
    cert_info=$(echo | timeout "$TIMEOUT" openssl s_client \
        -servername "$domain" \
        -connect "$domain:$PORT" 2>/dev/null | \
        openssl x509 -noout -enddate -subject 2>/dev/null) || true

    if [[ -z "$cert_info" ]]; then
        echo -e "${RED}  UNREACHABLE  ${RESET} $domain:$PORT"
        [[ -n "$OUTPUT_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] UNREACHABLE $domain" >> "$OUTPUT_FILE"
        return
    fi

    local end_date
    end_date=$(echo "$cert_info" | grep 'notAfter' | cut -d= -f2)

    local expiry_epoch
    expiry_epoch=$(date -d "$end_date" +%s 2>/dev/null || \
                   date -j -f "%b %d %T %Y %Z" "$end_date" +%s 2>/dev/null || echo 0)

    if [[ "$expiry_epoch" -eq 0 ]]; then
        echo -e "${YELLOW}  PARSE ERROR  ${RESET} $domain — could not parse expiry: $end_date"
        return
    fi

    local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
    local expiry_display
    expiry_display=$(date -d "@$expiry_epoch" '+%Y-%m-%d' 2>/dev/null || \
                     date -r "$expiry_epoch" '+%Y-%m-%d' 2>/dev/null || echo "$end_date")

    local status color
    if (( days_left < 0 )); then
        status="EXPIRED"
        color="$RED"
        (( expired_count++ )) || true
    elif (( days_left <= WARN_DAYS )); then
        status="WARNING"
        color="$YELLOW"
        (( warn_count++ )) || true
    else
        status="OK"
        color="$GREEN"
    fi

    printf "${color}  %-10s${RESET}  %-40s  Expires: %s  (%d days)\n" \
        "$status" "$domain" "$expiry_display" "$days_left"

    [[ -n "$OUTPUT_FILE" ]] && \
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $status $domain expires=$expiry_display days=$days_left" >> "$OUTPUT_FILE"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
warn_count=0
expired_count=0

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo ""
echo -e "${CYAN}  SSL Certificate Check — $TIMESTAMP${RESET}"
echo -e "${CYAN}  Warning threshold: $WARN_DAYS days  |  Port: $PORT  |  Domains: ${#DOMAINS[@]}${RESET}"
echo "  $(printf '%.0s─' {1..70})"

for domain in "${DOMAINS[@]}"; do
    check_domain "$domain"
done

echo "  $(printf '%.0s─' {1..70})"
echo -e "  Checked: ${#DOMAINS[@]}  |  ${YELLOW}Warning: ${warn_count}${RESET}  |  ${RED}Expired: ${expired_count}${RESET}"
echo ""

(( expired_count > 0 )) && exit 2
(( warn_count > 0 ))    && exit 1
exit 0
