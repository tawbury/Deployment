#!/usr/bin/env bash
################################################################################
# Declarative CD deploy script: parse infra/_shared/deploy/observer.yaml and
# run remote Docker commands via SSH. Clean restart logic (pull -> stop -> rm -> run).
# Usage: ./infra/_shared/scripts/deploy/deploy.sh [SPEC_YAML] [IMAGE_TAG] [SSH_HOST] [DEPLOY_DIR]
# Or set: DEPLOY_SPEC, IMAGE_TAG, SSH_HOST, SSH_KEY, DEPLOY_DIR (and optionally
# SSH_USER, SSH_PORT) via env. Sensitive data should come from GitHub Secrets.
# Run from repository root so that DEPLOY_SPEC path is correct.
################################################################################

set -euo pipefail

# ------------------------------------------------------------------------------
# Defaults and required env (override via GitHub Secrets / workflow)
# ------------------------------------------------------------------------------
DEPLOY_SPEC="${1:-${DEPLOY_SPEC:-infra/_shared/deploy/observer.yaml}}"
IMAGE_TAG="${2:-${IMAGE_TAG:-}}"
SSH_HOST="${3:-${SSH_HOST:-}}"
REMOTE_DEPLOY_DIR="${4:-${DEPLOY_DIR:-/opt/observer}}"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_PORT="${SSH_PORT:-22}"
# SSH_KEY: base64-encoded or raw private key; must be set for SSH
SSH_KEY="${SSH_KEY:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ------------------------------------------------------------------------------
# Parse YAML: use grep/sed/awk for portability (yq optional)
# ------------------------------------------------------------------------------
get_yaml() {
  local key="$1"
  local file="${2:-$DEPLOY_SPEC}"
  if command -v yq >/dev/null 2>&1; then
    if [ "$key" = "name" ]; then
      yq -r '.metadata.name // ""' "$file" 2>/dev/null
    else
      yq -r ".spec.$key // \"\"" "$file" 2>/dev/null
    fi
    return
  fi
  # Fallback: simple key: value extraction (handles "key: value" and "key: \"value\"")
  case "$key" in
    name)   grep -E '^\s*name:\s*' "$file" | sed -E 's/^\s*name:\s*["]?([^"]*)["]?.*/\1/' | tr -d ' \r' | head -1 ;;
    image)  grep -E '^\s*image:\s*' "$file" | sed -E 's/^\s*image:\s*["]?([^"]*)["]?.*/\1/' | tr -d ' \r' | head -1 ;;
    tag)    grep -E '^\s*tag:\s*' "$file" | sed -E 's/^\s*tag:\s*["]?([^"]*)["]?.*/\1/' | tr -d ' \r' | head -1 ;;
    port)   grep -E '^\s*port:\s*' "$file" | sed -E 's/^\s*port:\s*([0-9]+).*/\1/' | tr -d ' \r' | head -1 ;;
    replicas) grep -E '^\s*replicas:\s*' "$file" | sed -E 's/^\s*replicas:\s*([0-9]+).*/\1/' | tr -d ' \r' | head -1 ;;
    restart) grep -E '^\s*restart:\s*' "$file" | sed -E 's/^\s*restart:\s*["]?([^"]*)["]?.*/\1/' | tr -d ' \r' | head -1 ;;
    healthPath) grep -E '^\s*healthPath:\s*' "$file" | sed -E 's/^\s*healthPath:\s*["]?([^"]*)["]?.*/\1/' | tr -d ' \r' | head -1 ;;
    healthPort) grep -E '^\s*healthPort:\s*' "$file" | sed -E 's/^\s*healthPort:\s*([0-9]+).*/\1/' | tr -d ' \r' | head -1 ;;
    *) echo "" ;;
  esac
}

# ------------------------------------------------------------------------------
# Resolve image name and tag from spec + env
# ------------------------------------------------------------------------------
resolve_image() {
  NAME="$(get_yaml name)"
  IMAGE_BASE="$(get_yaml image)"
  SPEC_TAG="$(get_yaml tag)"
  PORT="$(get_yaml port)"
  REPLICAS="$(get_yaml replicas)"
  RESTART="$(get_yaml restart)"
  HEALTH_PATH="$(get_yaml healthPath)"
  HEALTH_PORT="$(get_yaml healthPort)"

  [ -z "$NAME" ] && NAME="observer"
  [ -z "$IMAGE_BASE" ] && IMAGE_BASE="ghcr.io/tawbury/observer"
  [ -z "$PORT" ] && PORT="8000"
  [ -z "$REPLICAS" ] && REPLICAS="1"
  [ -z "$RESTART" ] && RESTART="unless-stopped"
  [ -z "$HEALTH_PATH" ] && HEALTH_PATH="/health"
  [ -z "$HEALTH_PORT" ] && HEALTH_PORT="$PORT"

  FINAL_TAG="${SPEC_TAG:-$IMAGE_TAG}"
  if [ -z "$FINAL_TAG" ]; then
    log_error "IMAGE_TAG is required (workflow input or env)."
    exit 1
  fi
  FULL_IMAGE="${IMAGE_BASE}:${FINAL_TAG}"
}

# ------------------------------------------------------------------------------
# SSH wrapper: run remote command (key from env)
# ------------------------------------------------------------------------------
run_ssh() {
  if [ -n "${SSH_KEY:-}" ]; then
    local key_file
    key_file=$(mktemp)
    if echo "$SSH_KEY" | base64 -d >"$key_file" 2>/dev/null; then
      :
    else
      echo "$SSH_KEY" >"$key_file"
    fi
    chmod 600 "$key_file"
    ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null \
      -i "$key_file" -p "${SSH_PORT}" "${SSH_USER}@${SSH_HOST}" "$@"
    local exit_code=$?
    rm -f "$key_file"
    return $exit_code
  else
    ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null \
      -p "${SSH_PORT}" "${SSH_USER}@${SSH_HOST}" "$@"
  fi
}

# ------------------------------------------------------------------------------
# Ensure GHCR authentication on remote (for private images)
# ------------------------------------------------------------------------------
ensure_remote_ghcr_auth() {
  log_info "Checking GHCR authentication on remote host"
  # Test if we can pull from GHCR (will fail if private and not logged in)
  if run_ssh "sudo docker pull ghcr.io/tawbury/observer:latest >/dev/null 2>&1"; then
    log_info "GHCR auth OK or image is public"
    return 0
  fi
  
  # If GHCR_TOKEN env is set, use it to login on remote
  if [ -n "${GHCR_TOKEN:-}" ]; then
    log_info "Logging in to GHCR on remote host"
    run_ssh "echo '${GHCR_TOKEN}' | sudo docker login ghcr.io -u tawbury --password-stdin"
  else
    log_warn "GHCR pull may fail if image is private and no GHCR_TOKEN provided"
  fi
}

# ------------------------------------------------------------------------------
# Remote deploy: one container per replica (clean restart per instance)
# ------------------------------------------------------------------------------
deploy_remote() {
  local container_name host_port i
  for i in $(seq 1 "$REPLICAS"); do
    if [ "$REPLICAS" -eq 1 ]; then
      container_name="${NAME}"
      host_port="$PORT"
    else
      container_name="${NAME}-${i}"
      host_port=$((PORT + i - 1))
    fi

    log_info "Replica $i: container=${container_name} hostPort=${host_port}"

    run_ssh "sudo docker pull ${FULL_IMAGE}"
    run_ssh "sudo docker stop ${container_name} 2>/dev/null || true"
    run_ssh "sudo docker rm ${container_name} 2>/dev/null || true"
    run_ssh "sudo docker run -d \
      --name ${container_name} \
      --restart ${RESTART} \
      -p ${host_port}:${HEALTH_PORT} \
      ${FULL_IMAGE}"
  done
}

# ------------------------------------------------------------------------------
# Optional: health check on remote host
# ------------------------------------------------------------------------------
health_check_remote() {
  local base_url i host_port
  for i in $(seq 1 "$REPLICAS"); do
    if [ "$REPLICAS" -eq 1 ]; then
      host_port="$PORT"
    else
      host_port=$((PORT + i - 1))
    fi
    base_url="http://127.0.0.1:${host_port}${HEALTH_PATH}"
    log_info "Health check: $base_url"
    run_ssh "curl -sf --connect-timeout 5 ${base_url} || true"
  done
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
  log_info "Deploy spec: $DEPLOY_SPEC"
  if [ ! -f "$DEPLOY_SPEC" ]; then
    log_error "Spec file not found: $DEPLOY_SPEC"
    exit 1
  fi

  resolve_image
  log_info "Image: $FULL_IMAGE | Replicas: $REPLICAS | Port: $PORT"

  if [ -z "${SSH_HOST:-}" ]; then
    log_error "SSH_HOST is required (GitHub Secret or argument)."
    exit 1
  fi

  ensure_remote_ghcr_auth
  deploy_remote
  sleep 3
  health_check_remote || log_warn "Health check failed or skipped."
  log_info "Deploy finished: $FULL_IMAGE on $SSH_HOST"
}

main "$@"
