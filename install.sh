#!/usr/bin/env bash
# =============================================================================
# install.sh — Idempotent Contabo bootstrap for Optimize Common Infra
# =============================================================================
# Usage:
#   install.sh [--force-update <tool|all>] [--enable <profile>]... [--github-repo owner/repo]
#
# Default profiles: core observability mesh
# Ollama (ai): NEVER enabled unless --enable ai
# --force-update all: excludes ollama; kafka/rabbitmq/jaeger only if their profiles are enabled
# =============================================================================
set -euo pipefail

ROOT="/opt/optimizesolux/common-infra"
COMPOSE_PROJECT="optimizesolux-common"
GITHUB_REPO="${OCI_GITHUB_REPO:-AQUILA04/optimize-common-infra}"
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}/main"

FORCE_TOOLS=()
ENABLE_PROFILES=(core observability mesh)
SYNCED="${OCI_INIT_SYNCED:-0}"

ORIG_ARGS=("$@")

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-update)
      FORCE_TOOLS+=("$2")
      shift 2
      ;;
    --enable)
      ENABLE_PROFILES+=("$2")
      shift 2
      ;;
    --github-repo)
      GITHUB_REPO="$2"
      export OCI_GITHUB_REPO="$2"
      GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}/main"
      shift 2
      ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

# Dedupe profiles
mapfile -t ENABLE_PROFILES < <(printf '%s\n' "${ENABLE_PROFILES[@]}" | awk 'NF && !seen[$0]++')

has_profile() {
  local p="$1"
  for x in "${ENABLE_PROFILES[@]}"; do
    [[ "$x" == "$p" ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Sync from GitHub once
# ---------------------------------------------------------------------------
if [[ "$SYNCED" != "1" ]]; then
  echo ">>> [install] Syncing from GitHub ($GITHUB_REPO)..."
  mkdir -p "$ROOT"
  export OCI_GITHUB_REPO="$GITHUB_REPO"
  bash <(curl -sSL "$GITHUB_RAW/deploy/update-deploy.sh")
  curl -sSL "$GITHUB_RAW/install.sh" -o "$ROOT/install.sh"
  chmod +x "$ROOT/install.sh"
  export OCI_INIT_SYNCED=1
  exec "$ROOT/install.sh" "${ORIG_ARGS[@]}"
fi

cd "$ROOT"

# ---------------------------------------------------------------------------
# Docker + networks
# ---------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo ">>> [install] Installing Docker..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg git
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | tee /etc/apt/sources.list.d/docker.list >/dev/null
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

for net in traefik-public optimizesolux-common; do
  if docker network inspect "$net" >/dev/null 2>&1; then
    echo ">>> [install] Network $net exists"
  else
    docker network create "$net"
    echo ">>> [install] Network $net created"
  fi
done

mkdir -p "$ROOT/vault/data" "$ROOT/vault/keys"
# hashicorp/vault runs as uid/gid 100; host-owned dirs cause "permission denied" on /vault/data
chown -R 100:100 "$ROOT/vault/data" 2>/dev/null || true
chmod 700 "$ROOT/vault/data" "$ROOT/vault/keys" || true

if [[ ! -f "$ROOT/.env" ]]; then
  if [[ -f "$ROOT/deploy/../.env.example" ]] || [[ -f /tmp/x ]]; then
    :
  fi
  if curl -fsSL "$GITHUB_RAW/../.env.example" -o "$ROOT/.env.example" 2>/dev/null; then
    :
  fi
  if [[ -f "$ROOT/.env.example" ]]; then
    cp "$ROOT/.env.example" "$ROOT/.env"
  elif [[ -f /opt/optimizesolux/common-infra/deploy/../../.env.example ]]; then
    cp /opt/optimizesolux/common-infra/.env.example "$ROOT/.env" 2>/dev/null || true
  fi
  # Prefer synced copy next to compose after update-deploy
  if [[ ! -f "$ROOT/.env" ]] && [[ -f "$(dirname "$0")/.env.example" ]]; then
    cp "$(dirname "$0")/.env.example" "$ROOT/.env"
  fi
  echo ">>> [install] Created $ROOT/.env — EDIT SECRETS before production use"
  chmod 600 "$ROOT/.env" || true
fi

# Ensure .env.example is present for operators
curl -fsSL "https://raw.githubusercontent.com/${GITHUB_REPO}/main/.env.example" -o "$ROOT/.env.example" || true
if [[ ! -f "$ROOT/.env" && -f "$ROOT/.env.example" ]]; then
  cp "$ROOT/.env.example" "$ROOT/.env"
  chmod 600 "$ROOT/.env"
fi

COMPOSE_FILE="$ROOT/docker-compose.yml"
if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "ERROR: missing $COMPOSE_FILE" >&2
  exit 1
fi

PROFILE_ARGS=()
for p in "${ENABLE_PROFILES[@]}"; do
  PROFILE_ARGS+=(--profile "$p")
done

echo ">>> [install] Profiles: ${ENABLE_PROFILES[*]}"

compose() {
  docker compose -f "$COMPOSE_FILE" --project-name "$COMPOSE_PROJECT" --env-file "$ROOT/.env" "${PROFILE_ARGS[@]}" "$@"
}

# Map tool name → compose service(s)
tool_services() {
  case "$1" in
    vault) echo vault ;;
    keycloak) echo keycloak-db keycloak ;;
    redis) echo redis ;;
    artemis) echo artemis ;;
    minio) echo minio ;;
    mailpit) echo mailpit ;;
    pgadmin) echo pgadmin ;;
    gateway) echo gateway ;;
    eureka) echo eureka ;;
    otel|otel-collector) echo otel-collector ;;
    prometheus) echo prometheus ;;
    grafana) echo grafana ;;
    loki) echo loki ;;
    promtail) echo promtail ;;
    node-exporter) echo node-exporter ;;
    cadvisor) echo cadvisor ;;
    redis-exporter) echo redis-exporter ;;
    kafka) echo zookeeper kafka ;;
    rabbitmq) echo rabbitmq ;;
    jaeger) echo jaeger ;;
    ollama) echo ollama ;;
    *) echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# Force update
# ---------------------------------------------------------------------------
FORCE_SERVICES=()
for tool in "${FORCE_TOOLS[@]}"; do
  if [[ "$tool" == "all" ]]; then
    # all excludes ollama; opt-in profiles only if enabled
    for t in vault keycloak redis artemis minio mailpit pgadmin gateway eureka otel prometheus grafana loki promtail node-exporter cadvisor redis-exporter; do
      # shellcheck disable=SC2207
      FORCE_SERVICES+=($(tool_services "$t"))
    done
    has_profile kafka && FORCE_SERVICES+=($(tool_services kafka))
    has_profile rabbitmq && FORCE_SERVICES+=($(tool_services rabbitmq))
    has_profile tracing && FORCE_SERVICES+=($(tool_services jaeger))
  elif [[ "$tool" == "ollama" ]]; then
    if ! has_profile ai; then
      echo "ERROR: --force-update ollama requires --enable ai" >&2
      exit 1
    fi
    FORCE_SERVICES+=(ollama)
  else
    case "$tool" in
      kafka) has_profile kafka || { echo "ERROR: --force-update kafka requires --enable kafka" >&2; exit 1; } ;;
      rabbitmq) has_profile rabbitmq || { echo "ERROR: --force-update rabbitmq requires --enable rabbitmq" >&2; exit 1; } ;;
      jaeger) has_profile tracing || { echo "ERROR: --force-update jaeger requires --enable tracing" >&2; exit 1; } ;;
    esac
    svcs="$(tool_services "$tool")"
    if [[ -z "$svcs" ]]; then
      echo "ERROR: unknown tool '$tool'" >&2
      exit 1
    fi
    # shellcheck disable=SC2206
    FORCE_SERVICES+=($svcs)
  fi
done

if [[ ${#FORCE_SERVICES[@]} -gt 0 ]]; then
  mapfile -t FORCE_SERVICES < <(printf '%s\n' "${FORCE_SERVICES[@]}" | awk 'NF && !seen[$0]++')
  echo ">>> [install] Force-update: ${FORCE_SERVICES[*]}"
  if [[ -n "${GHCR_USERNAME:-}" && -n "${GHCR_TOKEN:-}" ]]; then
    echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin
  fi
  compose pull "${FORCE_SERVICES[@]}"
  compose up -d --force-recreate --no-deps "${FORCE_SERVICES[@]}"

  if printf '%s\n' "${FORCE_TOOLS[@]}" | grep -qxE 'keycloak|all'; then
    if [[ -x "$ROOT/deploy/bootstrap-biocollect-owner.sh" ]]; then
      echo ">>> [install] Bootstrapping BioCollect owner in Keycloak..."
      bash "$ROOT/deploy/bootstrap-biocollect-owner.sh" || echo ">>> [install] WARN: owner bootstrap failed (Keycloak may still be starting)"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Idempotent up: start missing / recreate only if not running
# ---------------------------------------------------------------------------
echo ">>> [install] Ensuring stack is up (idempotent)..."
if [[ -n "${GHCR_USERNAME:-}" && -n "${GHCR_TOKEN:-}" ]]; then
  echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin || true
fi

compose up -d --remove-orphans

echo ">>> [install] Status:"
compose ps

echo ">>> [install] Done."
echo "    Docs: NETWORKING.md — Vault init: docs/VAULT.md"
if has_profile ai; then
  echo "    WARN: profile ai (ollama) is enabled"
fi
