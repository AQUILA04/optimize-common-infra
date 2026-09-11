#!/usr/bin/env bash
# Idempotent: align Keycloak realm notification-hub with images/keycloak/realms/notification-hub-realm.json
# (--import-realm only creates missing realms; existing realms are not updated from JSON).
# Synced to Contabo via update-deploy.sh — run after force-update keycloak.
set -euo pipefail

ROOT="${OCI_ROOT:-/opt/optimizesolux/common-infra}"
COMPOSE_PROJECT="optimizesolux-common"
COMPOSE_FILE="$ROOT/docker-compose.yml"
REALM="notification-hub"
SENDER_ROLE="notification-sender"
ADMIN_ROLE="notification-admin"
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

echo ">>> [keycloak] Bootstrap realm alignment: ${REALM}"

kc config credentials \
  --server "http://localhost:8080" \
  --realm master \
  --user "$KC_ADMIN" \
  --password "$KC_ADMIN_PASSWORD" >/dev/null

ensure_role() {
  local name="$1" desc="$2"
  if kc get "roles/${name}" -r "$REALM" >/dev/null 2>&1; then
    echo ">>> [keycloak] Realm role ${name} already exists"
  else
    kc create roles -r "$REALM" -s "name=${name}" -s "description=${desc}"
    echo ">>> [keycloak] Created realm role ${name}"
  fi
}

client_internal_id() {
  local client_id="$1"
  kc get clients -r "$REALM" -q "clientId=${client_id}" --fields id --format csv --noquotes 2>/dev/null \
    | tail -1 | tr -d '[:space:]'
}

add_mapper_if_missing() {
  local internal_id="$1" name="$2"
  shift 2
  local mappers
  mappers="$(kc get "clients/${internal_id}/protocol-mappers/models" -r "$REALM" 2>/dev/null || true)"
  if echo "$mappers" | grep -q "\"name\"[[:space:]]*:[[:space:]]*\"${name}\""; then
    echo ">>> [keycloak] Mapper ${name} already present"
    return 0
  fi
  kc create "clients/${internal_id}/protocol-mappers/models" -r "$REALM" "$@"
  echo ">>> [keycloak] Created mapper ${name}"
}

assign_sender_role() {
  local internal_id="$1" client_id="$2"
  local sa_json sa_uid assigned
  sa_json="$(kc get "clients/${internal_id}/service-account-user" -r "$REALM" 2>/dev/null || true)"
  sa_uid="$(echo "$sa_json" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [[ -z "$sa_uid" ]]; then
    echo ">>> [keycloak] ERROR: no service account user for ${client_id}" >&2
    return 1
  fi
  assigned="$(kc get "users/${sa_uid}/role-mappings/realm" -r "$REALM" 2>/dev/null || true)"
  if echo "$assigned" | grep -q "\"name\"[[:space:]]*:[[:space:]]*\"${SENDER_ROLE}\""; then
    echo ">>> [keycloak] ${client_id} SA already has ${SENDER_ROLE}"
  else
    kc add-roles -r "$REALM" --uid "$sa_uid" --rolename "$SENDER_ROLE"
    echo ">>> [keycloak] Assigned ${SENDER_ROLE} to ${client_id} SA"
  fi
}

ensure_sender_client() {
  local client_id="$1" name="$2" description="$3" tenant_id="$4"
  local internal_id

  internal_id="$(client_internal_id "$client_id")"
  if [[ -n "$internal_id" ]]; then
    echo ">>> [keycloak] Client ${client_id} already exists (id=${internal_id})"
    kc update "clients/${internal_id}" -r "$REALM" \
      -s "name=${name}" \
      -s "description=${description}" \
      -s enabled=true \
      -s publicClient=false \
      -s serviceAccountsEnabled=true \
      -s standardFlowEnabled=false \
      -s directAccessGrantsEnabled=false \
      -s implicitFlowEnabled=false \
      -s 'protocol=openid-connect' >/dev/null
  else
    internal_id="$(kc create clients -r "$REALM" \
      -s "clientId=${client_id}" \
      -s "name=${name}" \
      -s "description=${description}" \
      -s enabled=true \
      -s publicClient=false \
      -s serviceAccountsEnabled=true \
      -s standardFlowEnabled=false \
      -s directAccessGrantsEnabled=false \
      -s implicitFlowEnabled=false \
      -s 'protocol=openid-connect' \
      -i | tr -d '[:space:]')"
    echo ">>> [keycloak] Created client ${client_id} (id=${internal_id})"
  fi

  if [[ -z "$internal_id" ]]; then
    echo ">>> [keycloak] ERROR: could not resolve internal id for ${client_id}" >&2
    return 1
  fi

  add_mapper_if_missing "$internal_id" "tenant_id" \
    -s name=tenant_id \
    -s protocol=openid-connect \
    -s protocolMapper=oidc-hardcoded-claim-mapper \
    -s 'config."claim.name"=tenant_id' \
    -s "config.\"claim.value\"=${tenant_id}" \
    -s 'config."jsonType.label"=String' \
    -s 'config."access.token.claim"=true' \
    -s 'config."id.token.claim"=false' \
    -s 'config."userinfo.token.claim"=false'

  add_mapper_if_missing "$internal_id" "audience-notification-hub-api" \
    -s name=audience-notification-hub-api \
    -s protocol=openid-connect \
    -s protocolMapper=oidc-audience-mapper \
    -s "config.\"included.client.audience\"=${AUDIENCE_CLIENT}" \
    -s 'config."access.token.claim"=true' \
    -s 'config."id.token.claim"=false'

  assign_sender_role "$internal_id" "$client_id"

  # Generate secret only if none exists — never rotate an existing secret
  local secret_json client_secret
  secret_json="$(kc get "clients/${internal_id}/client-secret" -r "$REALM" 2>/dev/null || true)"
  client_secret="$(echo "$secret_json" | sed -n 's/.*"value"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [[ -z "$client_secret" ]]; then
    kc create "clients/${internal_id}/client-secret" -r "$REALM" >/dev/null
    echo ">>> [keycloak] Generated new client secret for ${client_id}"
  else
    echo ">>> [keycloak] Client secret already set for ${client_id} (not rotated)"
  fi
}

# --- Roles ---
ensure_role "$SENDER_ROLE" "Send notifications via the hub API"
ensure_role "$ADMIN_ROLE" "Manage templates and admin endpoints"

# --- notification-hub-console ---
CONSOLE_ID="$(client_internal_id notification-hub-console)"
if [[ -n "$CONSOLE_ID" ]]; then
  echo ">>> [keycloak] Client notification-hub-console already exists (id=${CONSOLE_ID})"
  kc update "clients/${CONSOLE_ID}" -r "$REALM" \
    -s enabled=true \
    -s publicClient=true \
    -s directAccessGrantsEnabled=true \
    -s standardFlowEnabled=true \
    -s 'redirectUris=["https://notification.optimizesolux.com/*","http://localhost:4200/*"]' \
    -s 'webOrigins=["+"]' >/dev/null
else
  CONSOLE_ID="$(kc create clients -r "$REALM" \
    -s clientId=notification-hub-console \
    -s enabled=true \
    -s publicClient=true \
    -s directAccessGrantsEnabled=true \
    -s standardFlowEnabled=true \
    -s 'redirectUris=["https://notification.optimizesolux.com/*","http://localhost:4200/*"]' \
    -s 'webOrigins=["+"]' \
    -s 'protocol=openid-connect' \
    -i | tr -d '[:space:]')"
  echo ">>> [keycloak] Created client notification-hub-console (id=${CONSOLE_ID})"
fi

# --- notification-hub-api (resource / audience target) ---
API_ID="$(client_internal_id notification-hub-api)"
if [[ -n "$API_ID" ]]; then
  echo ">>> [keycloak] Client notification-hub-api already exists (id=${API_ID})"
  kc update "clients/${API_ID}" -r "$REALM" \
    -s enabled=true \
    -s publicClient=false \
    -s serviceAccountsEnabled=true \
    -s standardFlowEnabled=false \
    -s directAccessGrantsEnabled=false \
    -s 'protocol=openid-connect' >/dev/null
else
  API_ID="$(kc create clients -r "$REALM" \
    -s clientId=notification-hub-api \
    -s enabled=true \
    -s publicClient=false \
    -s serviceAccountsEnabled=true \
    -s standardFlowEnabled=false \
    -s directAccessGrantsEnabled=false \
    -s 'protocol=openid-connect' \
    -i | tr -d '[:space:]')"
  echo ">>> [keycloak] Created client notification-hub-api (id=${API_ID})"
fi
# Do not rotate api secret if present
API_SECRET_JSON="$(kc get "clients/${API_ID}/client-secret" -r "$REALM" 2>/dev/null || true)"
API_SECRET="$(echo "$API_SECRET_JSON" | sed -n 's/.*"value"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
if [[ -z "$API_SECRET" ]]; then
  kc create "clients/${API_ID}/client-secret" -r "$REALM" >/dev/null
  echo ">>> [keycloak] Generated new client secret for notification-hub-api"
else
  echo ">>> [keycloak] Client secret already set for notification-hub-api (not rotated)"
fi

# --- Sender clients (JSON SoT) ---
ensure_sender_client \
  "biocollect-notification-sender" \
  "BioCollect Notification Sender" \
  "BioCollect API — Client Credentials to send notifications" \
  "biocollect"

ensure_sender_client \
  "s2a" \
  "Amicale S2A Notification Sender" \
  "S2A API — Client Credentials for OTP activation via Notification Hub" \
  "s2a"

ensure_sender_client \
  "restoos" \
  "RestoOS Notification Sender" \
  "RestoOS API — Client Credentials to send invitations via Notification Hub" \
  "restoos"

echo ""
echo "================================================================"
echo " notification-hub realm aligned (roles + clients from realm JSON)"
echo "================================================================"
echo ">>> [keycloak] Roles:"
kc get roles -r "$REALM" --fields name --format csv --noquotes 2>/dev/null | sort -u || true
echo ">>> [keycloak] Clients:"
for c in notification-hub-console notification-hub-api biocollect-notification-sender s2a restoos; do
  id="$(client_internal_id "$c")"
  if [[ -n "$id" ]]; then
    echo "  OK  ${c} (${id})"
  else
    echo "  MISSING  ${c}"
  fi
done
echo ">>> [keycloak] Done."
