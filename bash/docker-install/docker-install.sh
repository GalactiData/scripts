#!/usr/bin/env bash
# docker-install.sh — Install Docker Engine + Compose plugin and add a user to the docker group (Ubuntu/Debian).

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
TARGET_USER=""          # user to add to the docker group (-u). Auto-detected if blank.
SKIP_GROUP=false        # --no-group to skip docker-group membership

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RESET='\033[0m'

info() { printf "${CYAN}==>${RESET} %s\n" "$*"; }
ok()   { printf "${GREEN}  ✓${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}  !${RESET} %s\n" "$*" >&2; }
err()  { printf "${RED}  ✗${RESET} %s\n" "$*" >&2; }

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install Docker Engine, the CLI, containerd, Buildx, and the Compose v2 plugin
from Docker's official apt repository, then add a user to the docker group.

Must be run as root (use sudo). Supports Ubuntu and Debian.

Options:
  -u <user>     User to add to the docker group
                (default: the sudo-invoking user, i.e. \$SUDO_USER)
  --no-group    Install Docker but do not modify docker-group membership
  -h, --help    Show this help

Examples:
  sudo $(basename "$0")
  sudo $(basename "$0") -u deploy
  curl -fsSL <raw-url>/docker-install.sh | sudo bash
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -u)         TARGET_USER="$2"; shift 2 ;;
        --no-group) SKIP_GROUP=true;  shift ;;
        -h|--help)  usage ;;
        -*)         err "Unknown option: $1"; usage ;;
        *)          err "Unexpected argument: $1"; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root. Re-run with: sudo $0 $*"
    exit 1
fi

if ! command -v apt-get &>/dev/null; then
    err "apt-get not found. This script supports Ubuntu/Debian only."
    exit 1
fi

# Distro id + codename from os-release
# shellcheck disable=SC1091
. /etc/os-release
DISTRO_ID="${ID:-ubuntu}"
CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"

case "$DISTRO_ID" in
    ubuntu|debian) ;;
    *) err "Unsupported distro '$DISTRO_ID' (needs Ubuntu or Debian)."; exit 1 ;;
esac

if [[ -z "$CODENAME" ]]; then
    err "Could not determine the distro codename from /etc/os-release."
    exit 1
fi

# Resolve the user that should join the docker group
if [[ "$SKIP_GROUP" == false && -z "$TARGET_USER" ]]; then
    TARGET_USER="${SUDO_USER:-}"
fi

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
info "Installing Docker on $DISTRO_ID ($CODENAME)"

info "Removing any old / conflicting packages"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    apt-get remove -y "$pkg" >/dev/null 2>&1 || true
done
ok "Old packages cleared"

info "Adding Docker's official GPG key and apt repository"
apt-get update -qq
apt-get install -y -qq ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

ARCH="$(dpkg --print-architecture)"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DISTRO_ID} ${CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update -qq
ok "Repository configured"

info "Installing Docker Engine, CLI, containerd, Buildx, and Compose plugin"
apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
ok "Docker packages installed"

info "Enabling and starting the docker service"
systemctl enable --now docker >/dev/null 2>&1 || true
ok "docker service enabled"

# ---------------------------------------------------------------------------
# docker group membership
# ---------------------------------------------------------------------------
if [[ "$SKIP_GROUP" == true ]]; then
    warn "Skipping docker-group membership (--no-group)"
elif [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    warn "No non-root user detected; not modifying the docker group."
    warn "Add one later with:  sudo usermod -aG docker <user>"
elif ! id "$TARGET_USER" &>/dev/null; then
    err "User '$TARGET_USER' does not exist; skipping docker-group step."
else
    usermod -aG docker "$TARGET_USER"
    ok "Added '$TARGET_USER' to the docker group"
    warn "Log out and back in (or run 'newgrp docker') for it to take effect."
fi

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
info "Versions"
docker --version || true
docker compose version || true

echo ""
ok "Done. Test with:  docker run --rm hello-world"
