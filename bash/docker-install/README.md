# docker-install.sh

Installs Docker Engine + the Compose v2 plugin from Docker's official apt repository on Ubuntu/Debian, then adds a user to the `docker` group.

## What It Does

Performs the full official Docker install: removes any old/conflicting packages, adds Docker's GPG key and apt repository for the detected distro (Ubuntu or Debian, read from `/etc/os-release`), installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, and `docker-compose-plugin`, enables the service, and adds a user to the `docker` group so Docker can run without `sudo`. Designed to be safe to run via `curl … | sudo bash` — it auto-detects the sudo-invoking user for the group step. Must be run as root.

## Usage

```bash
sudo ./docker-install.sh [OPTIONS]
```

## Options

| Flag | Argument | Description |
|------|----------|-------------|
| `-u` | `<user>` | User to add to the `docker` group (default: `$SUDO_USER`) |
| `--no-group` | | Install Docker but don't modify `docker`-group membership |
| `-h`, `--help` | | Show help and exit |

## Examples

```bash
# Install and add the invoking (sudo) user to the docker group
sudo ./docker-install.sh

# Add a specific user instead
sudo ./docker-install.sh -u deploy

# Install only, leave group membership alone
sudo ./docker-install.sh --no-group

# Direct download and run (replace <org>/<repo> with this repository)
curl -fsSL https://raw.githubusercontent.com/<org>/<repo>/main/bash/docker-install/docker-install.sh | sudo bash
```

## Notes

- **Ubuntu/Debian only** — uses the official Docker apt repo. Other distros exit with an error.
- **Compose v2** is installed as the `docker compose` (space) plugin, not the legacy `docker-compose` binary.
- After the group step, **log out and back in** (or run `newgrp docker`) for non-`sudo` Docker to take effect.
- `docker`-group membership is effectively **root-equivalent** on the host — only add trusted admin users.
- When piped as `curl … | sudo bash`, the user added to the group is `$SUDO_USER` (the account that ran `sudo`). Use `-u` to override.
