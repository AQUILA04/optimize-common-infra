#!/usr/bin/env bash
# Idempotent: ensure BioCollect owner exists in Keycloak realm biocollect.
# Deployed under deploy/ — synced to Contabo via update-deploy.sh.
set -euo pipefail

ROOT="${OCI_ROOT:-/opt/optimizesolux/common-infra}"
COMPOSE_PROJECT="optimizesolux-common"
COMPOSE_FILE="$ROOT/docker-compose.yml"

cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing $ROOT/.env" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

OWNER_EMAIL="${BIOCOLLECT_OWNER_EMAIL:-francis.ahonsou@gmail.com}"
OWNER_PASSWORD="${BIOCOLLECT_OWNER_PASSWORD:-BioCollect-Owner-ChangeMe!}"
KC_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KC_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PASSWORD required}"

compose() {
  docker compose -f "$COMPOSE_FILE" --project-name "$COMPOSE_PROJECT" --env-file "$ROOT/.env" \
    --profile core --profile observability --profile mesh "$@"
}

kc() {
  compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"
}

echo ">>> [keycloak] Bootstrap owner $OWNER_EMAIL in realm biocollect"

kc config credentials \
  --server "http://localhost:8080" \
  --realm master \
  --user "$KC_ADMIN" \
  --password "$KC_ADMIN_PASSWORD" >/dev/null

existing="$(kc get users -r biocollect -q "email=$OWNER_EMAIL" 2>/dev/null || true)"
if echo "$existing" | grep -q '"id"'; then
  echo ">>> [keycloak] User already exists — skipping create"
  exit 0
fi

user_id="$(kc create users -r biocollect \
  -s "username=$OWNER_EMAIL" \
  -s "email=$OWNER_EMAIL" \
  -s emailVerified=true \
  -s enabled=true \
  -s firstName=Francis \
  -s lastName=Ahonsou \
  -i)"

kc set-password -r biocollect --userid "$user_id" --new-password "$OWNER_PASSWORD" --temporary

echo ">>> [keycloak] Created owner user (temporary password — change on first login)"
