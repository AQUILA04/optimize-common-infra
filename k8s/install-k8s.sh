#!/usr/bin/env bash
# =============================================================================
# k8s/install-k8s.sh — Idempotent K8s install for Optimize Common Infra
# =============================================================================
# Usage:
#   ./k8s/install-k8s.sh [--force-update <tool|all>] [--enable <profile>]...
#
# Default profiles: core observability mesh
# ai / ollama: NEVER unless --enable ai
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
NS="optimizesolux-common"
FORCE_TOOLS=()
ENABLE_PROFILES=(core observability mesh)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-update) FORCE_TOOLS+=("$2"); shift 2 ;;
    --enable) ENABLE_PROFILES+=("$2"); shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

mapfile -t ENABLE_PROFILES < <(printf '%s\n' "${ENABLE_PROFILES[@]}" | awk 'NF && !seen[$0]++')

has_profile() {
  local p="$1"
  for x in "${ENABLE_PROFILES[@]}"; do [[ "$x" == "$p" ]] && return 0; done
  return 1
}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is required" >&2
  exit 1
fi

echo ">>> [k8s] Namespace $NS"
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create namespace "$NS"

OVERLAYS=("$ROOT/overlays/prod")
has_profile kafka && OVERLAYS+=("$ROOT/overlays/kafka")
has_profile rabbitmq && OVERLAYS+=("$ROOT/overlays/rabbitmq")
has_profile tracing && OVERLAYS+=("$ROOT/overlays/tracing")
has_profile ai && OVERLAYS+=("$ROOT/overlays/ai")

apply_overlay() {
  local path="$1"
  if [[ ! -d "$path" ]]; then
    echo "WARN: missing overlay $path — skip"
    return 0
  fi
  echo ">>> [k8s] apply $path"
  kubectl apply -k "$path"
}

for o in "${OVERLAYS[@]}"; do
  apply_overlay "$o"
done

# Force-update: rollout restart matching deployments
restart_for_tool() {
  case "$1" in
    vault) kubectl -n "$NS" rollout restart deploy/vault 2>/dev/null || true ;;
    keycloak) kubectl -n "$NS" rollout restart deploy/keycloak deploy/keycloak-db 2>/dev/null || true ;;
    redis) kubectl -n "$NS" rollout restart deploy/redis 2>/dev/null || true ;;
    artemis) kubectl -n "$NS" rollout restart deploy/artemis 2>/dev/null || true ;;
    minio) kubectl -n "$NS" rollout restart deploy/minio 2>/dev/null || true ;;
    mailpit) kubectl -n "$NS" rollout restart deploy/mailpit 2>/dev/null || true ;;
    pgadmin) kubectl -n "$NS" rollout restart deploy/pgadmin 2>/dev/null || true ;;
    gateway) kubectl -n "$NS" rollout restart deploy/gateway 2>/dev/null || true ;;
    eureka) kubectl -n "$NS" rollout restart deploy/eureka 2>/dev/null || true ;;
    otel|otel-collector) kubectl -n "$NS" rollout restart deploy/otel-collector 2>/dev/null || true ;;
    prometheus) kubectl -n "$NS" rollout restart deploy/prometheus 2>/dev/null || true ;;
    grafana) kubectl -n "$NS" rollout restart deploy/grafana 2>/dev/null || true ;;
    loki) kubectl -n "$NS" rollout restart deploy/loki 2>/dev/null || true ;;
    promtail) kubectl -n "$NS" rollout restart daemonset/promtail 2>/dev/null || true ;;
    node-exporter) kubectl -n "$NS" rollout restart daemonset/node-exporter 2>/dev/null || true ;;
    kafka) kubectl -n "$NS" rollout restart deploy/kafka deploy/zookeeper 2>/dev/null || true ;;
    rabbitmq) kubectl -n "$NS" rollout restart deploy/rabbitmq 2>/dev/null || true ;;
    jaeger) kubectl -n "$NS" rollout restart deploy/jaeger 2>/dev/null || true ;;
    ollama)
      if ! has_profile ai; then
        echo "ERROR: --force-update ollama requires --enable ai" >&2
        exit 1
      fi
      kubectl -n "$NS" rollout restart deploy/ollama 2>/dev/null || true
      ;;
    all)
      for t in vault keycloak redis artemis minio mailpit pgadmin gateway eureka otel prometheus grafana loki promtail node-exporter kafka rabbitmq jaeger; do
        restart_for_tool "$t"
      done
      ;;
    *) echo "Unknown tool: $1" >&2; exit 1 ;;
  esac
}

for tool in "${FORCE_TOOLS[@]}"; do
  echo ">>> [k8s] force-update $tool"
  restart_for_tool "$tool"
done

echo ">>> [k8s] Done. Pods:"
kubectl -n "$NS" get pods -o wide
