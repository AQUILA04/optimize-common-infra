#!/usr/bin/env bash
# Idempotent: provision Keycloak client "s2a" in realm notification-hub
# for S2A OTP via Notification Hub (client credentials + tenant_id + audience).
# Synced to Contabo via update-deploy.sh — run after force-update keycloak.
set -euo pipefail

ROOT="${OCI_ROOT:-/opt/optimizesolux/common-infra}"
COMPOSE_PROJECT="optimizesolux-common"
COMPOSE_FILE="$ROOT/docker-compose.yml"
REALM="notification-hub"
CLIENT_ID="s2a"
TENANT_ID="s2a"
ROLE_NAME="notification-sender"
AUDIENCE_CLIENT="notification-hub-api"

cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Missing $ROOT/.env" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

KC_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KC_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PASSWORD required}"

compose() {
  docker compose -f "$COMPOSE_FILE" --project-name "$COMPOSE_PROJECT" --env-file "$ROOT/.env" \
    --profile core --profile observability --profile mesh "$@"
}

kc() {
  compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"
}

echo ">>> [keycloak] Bootstrap notification-hub client: ${CLIENT_ID}"

kc config credentials \
  --server "http://localhost:8080" \
  --realm master \
  --user "$KC_ADMIN" \
  --password "$KC_ADMIN_PASSWORD" >/dev/null

# --- Realm role notification-sender ---
if kc get roles/"$ROLE_NAME" -r "$REALM" >/dev/null 2>&1; then
  echo ">>> [keycloak] Realm role ${ROLE_NAME} already exists"
else
  kc create roles -r "$REALM" \
    -s "name=$ROLE_NAME" \
    -s "description=Send notifications via the hub API"
  echo ">>> [keycloak] Created realm role ${ROLE_NAME}"
fi

client_internal_id() {
  kc get clients -r "$REALM" -q "clientId=$CLIENT_ID" --fields id --format csv --noquotes 2>/dev/null | tail -1 | tr -d '[:space:]'
}

# --- Client s2a ---
INTERNAL_ID="$(client_internal_id)"
if [[ -n "$INTERNAL_ID" ]]; then
  echo ">>> [keycloak] Client ${CLIENT_ID} already exists (id=${INTERNAL_ID})"
else
  INTERNAL_ID="$(kc create clients -r "$REALM" \
    -s "clientId=$CLIENT_ID" \
    -s "name=Amicale S2A Notification Sender" \
    -s "description=S2A API — Client Credentials for OTP activation via Notification Hub" \
    -s enabled=true \
    -s publicClient=false \
    -s serviceAccountsEnabled=true \
    -s standardFlowEnabled=false \
    -s directAccessGrantsEnabled=false \
    -s implicitFlowEnabled=false \
    -s 'protocol=openid-connect' \
    -i | tr -d '[:space:]')"
  echo ">>> [keycloak] Created client ${CLIENT_ID} (id=${INTERNAL_ID})"
fi

if [[ -z "$INTERNAL_ID" ]]; then
  echo ">>> [keycloak] ERROR: could not resolve internal client id" >&2
  exit 1
fi

# --- Protocol mappers on client ---
add_mapper_if_missing() {
  local name="$1"
  shift
  local mappers
  mappers="$(kc get "clients/${INTERNAL_ID}/protocol-mappers/models" -r "$REALM" 2>/dev/null || true)"
  if echo "$mappers" | grep -q "\"name\"[[:space:]]*:[[:space:]]*\"${name}\""; then
    echo ">>> [keycloak] Mapper ${name} already present"
    return 0
  fi
  kc create "clients/${INTERNAL_ID}/protocol-mappers/models" -r "$REALM" "$@"
  echo ">>> [keycloak] Created mapper ${name}"
}

add_mapper_if_missing "tenant_id" \
  -s name=tenant_id \
  -s protocol=openid-connect \
  -s protocolMapper=oidc-hardcoded-claim-mapper \
  -s 'config."claim.name"=tenant_id' \
  -s "config.\"claim.value\"=$TENANT_ID" \
  -s 'config."jsonType.label"=String' \
  -s 'config."access.token.claim"=true' \
  -s 'config."id.token.claim"=false' \
  -s 'config."userinfo.token.claim"=false'

add_mapper_if_missing "audience-notification-hub-api" \
  -s name=audience-notification-hub-api \
  -s protocol=openid-connect \
  -s protocolMapper=oidc-audience-mapper \
  -s "config.\"included.client.audience\"=$AUDIENCE_CLIENT" \
  -s 'config."access.token.claim"=true' \
  -s 'config."id.token.claim"=false'

# --- Service account role ---
SA_JSON="$(kc get "clients/${INTERNAL_ID}/service-account-user" -r "$REALM" 2>/dev/null || true)"
SA_UID="$(echo "$SA_JSON" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

if [[ -z "$SA_UID" ]]; then
  echo ">>> [keycloak] ERROR: no service account user for ${CLIENT_ID}" >&2
  exit 1
fi

ASSIGNED="$(kc get "users/${SA_UID}/role-mappings/realm" -r "$REALM" 2>/dev/null || true)"
if echo "$ASSIGNED" | grep -q "\"name\"[[:space:]]*:[[:space:]]*\"${ROLE_NAME}\""; then
  echo ">>> [keycloak] Service account already has role ${ROLE_NAME}"
else
  kc add-roles -r "$REALM" --uid "$SA_UID" --rolename "$ROLE_NAME"
  echo ">>> [keycloak] Assigned ${ROLE_NAME} to service account"
fi

# --- Client secret (regenerate only if missing) ---
SECRET_JSON="$(kc get "clients/${INTERNAL_ID}/client-secret" -r "$REALM" 2>/dev/null || true)"
CLIENT_SECRET="$(echo "$SECRET_JSON" | sed -n 's/.*"value"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

if [[ -z "$CLIENT_SECRET" ]]; then
  SECRET_JSON="$(kc create "clients/${INTERNAL_ID}/client-secret" -r "$REALM")"
  CLIENT_SECRET="$(echo "$SECRET_JSON" | sed -n 's/.*"value"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  echo ">>> [keycloak] Generated new client secret"
fi

echo ""
echo "================================================================"
echo " S2A Keycloak client ready (realm: ${REALM}, clientId: ${CLIENT_ID})"
echo "================================================================"
echo ""
echo "Copy this secret into GitHub:"
echo "  gh secret set NOTIFICATION_HUB_OAUTH_CLIENT_SECRET -R AQUILA04/S2A -b \"${CLIENT_SECRET}\""
echo ""
echo "OAuth token URI (verify in S2A secrets):"
echo "  https://notification-auth.optimizesolux.com/realms/notification-hub/protocol/openid-connect/token"
echo "  (or https://auth.optimizesolux.com/realms/notification-hub/protocol/openid-connect/token)"
echo ""
echo ">>> [keycloak] Smoke test: client credentials token..."
TOKEN_JSON="$(curl -sS -X POST \
  "${KC_TOKEN_URI:-https://auth.optimizesolux.com/realms/notification-hub/protocol/openid-connect/token}" \
  -d "grant_type=client_credentials" \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${CLIENT_SECRET}" 2>/dev/null || true)"

if echo "$TOKEN_JSON" | grep -q access_token; then
  echo ">>> [keycloak] OK — token obtained via public auth URL"
else
  echo ">>> [keycloak] WARN — public token URL failed (client may still work from VPS internal network)"
  echo "    Response: ${TOKEN_JSON:0:200}"
  # Try internal from keycloak container network isn't needed if public fails due to hostname
fi

echo ">>> [keycloak] Done."
