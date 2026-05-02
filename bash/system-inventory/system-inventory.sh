#!/usr/bin/env bash
# system-inventory.sh — Collect a hardware and software inventory snapshot of a Linux machine.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
OUTPUT_FILE=""
FORMAT="text"        # text | csv
SKIP_PACKAGES=false

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Collect a hardware, OS, network, and software inventory of the local machine.

Options:
  -o <file>          Write output to this file (default: stdout)
  --format <fmt>     Output format: text (default) or csv
  --skip-packages    Skip the installed package list (faster)
  -h, --help         Show this help

Examples:
  $(basename "$0")
  $(basename "$0") -o /tmp/inventory.txt
  $(basename "$0") --format csv -o /tmp/inventory.csv
  $(basename "$0") --skip-packages
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)             OUTPUT_FILE="$2"; shift 2 ;;
        --format)       FORMAT="$2";      shift 2 ;;
        --skip-packages) SKIP_PACKAGES=true; shift ;;
        -h|--help)      usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
TMPOUT=$(mktemp)
trap 'rm -f "$TMPOUT"' EXIT

out() { echo "$*" >> "$TMPOUT"; }

section() {
    if [[ "$FORMAT" == "csv" ]]; then
        out ""
        out "### $1 ###"
    else
        out ""
        out "━━━  $1  $(printf '%.0s━' {1..50})"
        out ""
    fi
}

kv() {
    local key="$1" val="$2"
    if [[ "$FORMAT" == "csv" ]]; then
        out "\"$key\",\"$val\""
    else
        printf '  %-26s %s\n' "$key" "$val" >> "$TMPOUT"
    fi
}

# ---------------------------------------------------------------------------
# Data collection
# ---------------------------------------------------------------------------
HOSTNAME=$(hostname -f 2>/dev/null || hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

out "System Inventory — $HOSTNAME — $TIMESTAMP"
[[ "$FORMAT" == "csv" ]] && out "key,value"

# -- OS / System --
section "SYSTEM"
kv "Hostname"      "$HOSTNAME"
kv "OS"            "$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || uname -s)"
kv "Kernel"        "$(uname -r)"
kv "Architecture"  "$(uname -m)"

# Uptime
if command -v uptime &>/dev/null; then
    kv "Uptime" "$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')"
fi

# Last boot
if command -v who &>/dev/null; then
    LASTBOOT=$(who -b 2>/dev/null | awk '{print $3, $4}')
    [[ -n "$LASTBOOT" ]] && kv "Last Boot" "$LASTBOOT"
fi

# Manufacturer / model
if [[ -r /sys/class/dmi/id/sys_vendor ]]; then
    kv "Manufacturer" "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)"
    kv "Model"        "$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
fi

# Serial number (may require root)
if [[ -r /sys/class/dmi/id/product_serial ]]; then
    kv "Serial Number" "$(cat /sys/class/dmi/id/product_serial 2>/dev/null)"
fi

# -- CPU --
section "CPU"
if command -v lscpu &>/dev/null; then
    kv "Model"           "$(lscpu | grep 'Model name' | sed 's/Model name:\s*//')"
    kv "Sockets"         "$(lscpu | grep '^Socket(s)' | awk '{print $2}')"
    kv "Cores per socket" "$(lscpu | grep 'Core(s) per socket' | awk '{print $NF}')"
    kv "Threads per core" "$(lscpu | grep 'Thread(s) per core' | awk '{print $NF}')"
    kv "Logical CPUs"    "$(lscpu | grep '^CPU(s):' | awk '{print $2}')"
    kv "Max MHz"         "$(lscpu | grep 'CPU max MHz' | awk '{print $NF}' || echo 'N/A')"
    kv "Architecture"    "$(lscpu | grep '^Architecture' | awk '{print $2}')"
fi

# -- Memory --
section "MEMORY"
if [[ -r /proc/meminfo ]]; then
    total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    free_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    used_kb=$(( total_kb - free_kb ))
    kv "Total"     "$(awk "BEGIN{printf \"%.2f GB\", $total_kb/1048576}")"
    kv "Used"      "$(awk "BEGIN{printf \"%.2f GB\", $used_kb/1048576}")"
    kv "Available" "$(awk "BEGIN{printf \"%.2f GB\", $free_kb/1048576}")"
    kv "Used %"    "$(awk "BEGIN{printf \"%.1f%%\", $used_kb/$total_kb*100}")"
fi

# -- Disks --
section "DISKS"
if [[ "$FORMAT" == "csv" ]]; then
    out "filesystem,size,used,available,use%,mount"
    df -h --output=source,size,used,avail,pcent,target 2>/dev/null | tail -n +2 | \
        grep -v '^tmpfs\|^devtmpfs\|^udev\|^none\|^overlay\|^squashfs' | \
        while IFS= read -r line; do out "$line"; done
else
    df -h --output=source,size,used,avail,pcent,target 2>/dev/null | \
        grep -v '^tmpfs\|^devtmpfs\|^udev\|^none\|^overlay\|^squashfs\|^Filesystem'
fi

# -- GPU --
section "GPU"
if command -v lspci &>/dev/null; then
    gpus=$(lspci | grep -i 'vga\|3d\|display' 2>/dev/null)
    if [[ -n "$gpus" ]]; then
        while IFS= read -r gpu; do
            kv "GPU" "$(echo "$gpu" | sed 's/^[^ ]* //')"
        done <<< "$gpus"
    else
        kv "GPU" "Not detected"
    fi
fi

# -- Network --
section "NETWORK"
if command -v ip &>/dev/null; then
    if [[ "$FORMAT" == "csv" ]]; then
        out "interface,mac,ip_address,prefix"
    fi
    ip -o link show 2>/dev/null | grep -v '^[0-9]*: lo' | awk '{print $2, $17}' | \
    while read -r iface mac; do
        iface="${iface%:}"
        ips=$(ip -o addr show "$iface" 2>/dev/null | awk '{print $4}')
        if [[ -n "$ips" ]]; then
            while IFS= read -r addr; do
                if [[ "$FORMAT" == "csv" ]]; then
                    out "\"$iface\",\"$mac\",\"${addr%/*}\",\"${addr#*/}\""
                else
                    kv "$iface ($mac)" "$addr"
                fi
            done <<< "$ips"
        fi
    done
fi

# -- Packages --
if [[ "$SKIP_PACKAGES" == false ]]; then
    section "INSTALLED PACKAGES"
    if command -v dpkg &>/dev/null; then
        pkg_count=$(dpkg -l 2>/dev/null | grep -c '^ii')
        kv "Package manager" "dpkg/apt"
        kv "Installed count" "$pkg_count"
        if [[ "$FORMAT" == "csv" ]]; then
            out "name,version,architecture,description"
            dpkg -l 2>/dev/null | grep '^ii' | awk '{print "\"" $2 "\",\"" $3 "\",\"" $4 "\",\"" $5 "\""}' >> "$TMPOUT"
        else
            dpkg -l 2>/dev/null | grep '^ii' | awk '{printf "  %-40s %s\n", $2, $3}' >> "$TMPOUT"
        fi
    elif command -v rpm &>/dev/null; then
        pkg_count=$(rpm -qa 2>/dev/null | wc -l)
        kv "Package manager" "rpm"
        kv "Installed count" "$pkg_count"
        if [[ "$FORMAT" == "csv" ]]; then
            out "name,version"
            rpm -qa --queryformat '"%{NAME}","%{VERSION}-%{RELEASE}"\n' 2>/dev/null >> "$TMPOUT"
        else
            rpm -qa --queryformat '  %-40{NAME} %{VERSION}-%{RELEASE}\n' 2>/dev/null >> "$TMPOUT"
        fi
    elif command -v pacman &>/dev/null; then
        pkg_count=$(pacman -Q 2>/dev/null | wc -l)
        kv "Package manager" "pacman"
        kv "Installed count" "$pkg_count"
        pacman -Q 2>/dev/null | awk '{printf "  %-40s %s\n", $1, $2}' >> "$TMPOUT"
    else
        kv "Package manager" "Unknown — could not enumerate packages"
    fi
fi

out ""

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [[ -n "$OUTPUT_FILE" ]]; then
    cp "$TMPOUT" "$OUTPUT_FILE"
    echo "Inventory saved: $OUTPUT_FILE"
else
    cat "$TMPOUT"
fi
