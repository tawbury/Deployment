#!/usr/bin/env bash
set -euo pipefail

# Oracle VM Docker + Compose v2 bootstrap
# Usage: bash oracle_bootstrap.sh

log() { echo "[bootstrap] $*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

PKG=""
SUDO_PASSWORD="${SUDO_PASSWORD:-}"
run_sudo() {
  # Use sudo -S and read password from env if provided; works with NOPASSWD too
  if [ -n "$SUDO_PASSWORD" ]; then
    echo "$SUDO_PASSWORD" | sudo -S -p '' "$@"
  else
    sudo -S -p '' "$@"
  fi
}
if require_cmd dnf; then
  PKG=dnf
elif require_cmd yum; then
  PKG=yum
elif require_cmd apt; then
  PKG=apt
else
  log "No supported package manager found (dnf/yum/apt)."
  exit 1
fi

log "Detected package manager: ${PKG}"

# Update index
if [ "$PKG" = "apt" ]; then
  run_sudo apt-get update -y
fi

# Install Docker Engine
log "Installing Docker Engine"
case "$PKG" in
  dnf)
    run_sudo dnf install -y docker
    ;;
  yum)
    run_sudo yum install -y docker
    ;;
  apt)
    run_sudo apt-get install -y docker.io
    ;;
esac

# Enable + start Docker
log "Enabling and starting docker service"
run_sudo systemctl enable --now docker

# Add current user to docker group (optional)
if getent group docker >/dev/null 2>&1; then
  run_sudo usermod -aG docker "$USER" || true
fi

# Install Docker Compose v2 (CLI plugin) if not present
if ! docker compose version >/dev/null 2>&1; then
  log "Installing Docker Compose v2 plugin"
  mkdir -p ~/.docker/cli-plugins
  ARCH=$(uname -m)
  # Map common arch names
  case "$ARCH" in
    x86_64|amd64)
      COMP_ARCH="x86_64";;
    aarch64|arm64)
      COMP_ARCH="aarch64";;
    *)
      log "Unsupported architecture: $ARCH"
      exit 1;;
  esac
  curl -fsSL "https://github.com/docker/compose/releases/download/v2.24.7/docker-compose-linux-${COMP_ARCH}" \
    -o ~/.docker/cli-plugins/docker-compose
  chmod +x ~/.docker/cli-plugins/docker-compose
fi

log "Docker version: $(docker --version)"
log "Compose version: $(docker compose version || echo 'compose plugin not detected')"

# Prepare workspace directory layout
log "Preparing ~/workspace directory"
mkdir -p ~/workspace

log "Bootstrap complete. If you added user to docker group, re-login may be required."
