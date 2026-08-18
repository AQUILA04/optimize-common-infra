#!/usr/bin/env bash
# Provisionne les dépendances communes et secrets du produit ImpactC.
# À exécuter sur Contabo, après l'initialisation et le déverrouillage de Vault.
set -euo pipefail

COMMON_INFRA_ROOT="${COMMON_INFRA_ROOT:-/opt/optimizesolux/common-infra}"
COMPOSE_FILE="${COMMON_INFRA_ROOT}/docker-compose.yml"
COMPOSE_ENV_FILE="${COMMON_INFRA_ROOT}/.env"
POLICY_DIR="${COMMON_INFRA_ROOT}/deploy/impactc/policies"
MC_IMAGE="${MC_IMAGE:-minio/mc:RELEASE.2024-12-18T13-15-44Z}"
MINIO_ALIAS="impactc-provisioner"
MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://minio:9000}"
MINIO_REGION="${MINIO_REGION:-us-east-1}"
IMPACTC_MEDIA_BUCKET="${IMPACTC_MEDIA_BUCKET:-impactc-media}"
IMPACTC_MOBILE_RELEASES_BUCKET="${IMPACTC_MOBILE_RELEASES_BUCKET:-impactc-mobile-releases}"
IMPACTC_DB_USER="${IMPACTC_DB_USER:-impactc}"
IMPACTC_KEYCLOAK_ISSUER="${IMPACTC_KEYCLOAK_ISSUER:-https://auth.optimizesolux.com/realms/impactc}"
IMPACTC_KEYCLOAK_AUDIENCE="${IMPACTC_KEYCLOAK_AUDIENCE:-impactc-backoffice}"
NOTIFICATION_HUB_BASE_URL="${NOTIFICATION_HUB_BASE_URL:-https://notification-api.optimizesolux.com}"
NOTIFICATION_HUB_FROM="${NOTIFICATION_HUB_FROM:-notifications@optimizesolux.com}"
NOTIFICATION_HUB_OAUTH_TOKEN_URL="${NOTIFICATION_HUB_OAUTH_TOKEN_URL:-https://auth.optimizesolux.com/realms/notification-hub/protocol/openid-connect/token}"
NOTIFICATION_HUB_OAUTH_CLIENT_ID="${NOTIFICATION_HUB_OAUTH_CLIENT_ID:-impactc-notification-sender}"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "${name} is required"
}

compose() {
  docker compose --project-name optimizesolux-common --env-file "$COMPOSE_ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

vault_exec() {
  compose --profile core exec -T \
    -e VAULT_TOKEN \
    -e IMPACTC_DB_USER \
    -e IMPACTC_DB_PASSWORD \
    -e IMPACTC_JWT_ACCESS_SECRET \
    -e IMPACTC_JWT_REFRESH_SECRET \
    -e IMPACTC_CHAT_ENCRYPTION_KEY \
    -e IMPACTC_REDIS_PASSWORD \
    -e IMPACTC_S3_ACCESS_KEY \
    -e IMPACTC_S3_SECRET_KEY \
    -e IMPACTC_RELEASES_ACCESS_KEY \
    -e IMPACTC_RELEASES_SECRET_KEY \
    -e IMPACTC_KEYCLOAK_ISSUER \
    -e IMPACTC_KEYCLOAK_AUDIENCE \
    -e NOTIFICATION_HUB_BASE_URL \
    -e NOTIFICATION_HUB_FROM \
    -e NOTIFICATION_HUB_OAUTH_TOKEN_URL \
    -e NOTIFICATION_HUB_OAUTH_CLIENT_ID \
    -e NOTIFICATION_HUB_OAUTH_CLIENT_SECRET \
    -e MINIO_ENDPOINT \
    -e MINIO_REGION \
    -e IMPACTC_MEDIA_BUCKET \
    -e IMPACTC_MOBILE_RELEASES_BUCKET \
    vault sh -ec "$1"
}

command -v docker >/dev/null 2>&1 || fail "docker is required"
[[ -f "$COMPOSE_FILE" ]] || fail "common-infra compose not found at ${COMPOSE_FILE}"
[[ -f "$COMPOSE_ENV_FILE" ]] || fail "common-infra environment file not found at ${COMPOSE_ENV_FILE}"
[[ -d "$POLICY_DIR" ]] || fail "MinIO policies not found at ${POLICY_DIR}"

for network in optimizesolux-common traefik-public; do
  docker network inspect "$network" >/dev/null 2>&1 || fail "required Docker network '${network}' is absent"
done

for service in minio redis vault; do
  compose --profile core ps --status running "$service" | grep -q "$service" || fail "common service '${service}' is not running"
done

require MINIO_ROOT_USER
require MINIO_ROOT_PASSWORD
require VAULT_TOKEN
require IMPACTC_DB_PASSWORD
require IMPACTC_JWT_ACCESS_SECRET
require IMPACTC_JWT_REFRESH_SECRET
require IMPACTC_CHAT_ENCRYPTION_KEY
require IMPACTC_REDIS_PASSWORD
require IMPACTC_S3_ACCESS_KEY
require IMPACTC_S3_SECRET_KEY
require IMPACTC_RELEASES_ACCESS_KEY
require IMPACTC_RELEASES_SECRET_KEY
require NOTIFICATION_HUB_OAUTH_CLIENT_SECRET

[[ ${#IMPACTC_CHAT_ENCRYPTION_KEY} -eq 32 ]] || fail "IMPACTC_CHAT_ENCRYPTION_KEY must contain exactly 32 bytes"
[[ "$IMPACTC_MEDIA_BUCKET" == "impactc-media" ]] || fail "the media policy is intentionally bound to impactc-media"
[[ "$IMPACTC_MOBILE_RELEASES_BUCKET" == "impactc-mobile-releases" ]] || fail "the APK policy is intentionally bound to impactc-mobile-releases"

export VAULT_TOKEN IMPACTC_DB_USER IMPACTC_DB_PASSWORD IMPACTC_JWT_ACCESS_SECRET IMPACTC_JWT_REFRESH_SECRET
export IMPACTC_CHAT_ENCRYPTION_KEY IMPACTC_REDIS_PASSWORD IMPACTC_S3_ACCESS_KEY IMPACTC_S3_SECRET_KEY
export IMPACTC_RELEASES_ACCESS_KEY IMPACTC_RELEASES_SECRET_KEY IMPACTC_KEYCLOAK_ISSUER IMPACTC_KEYCLOAK_AUDIENCE
export NOTIFICATION_HUB_BASE_URL NOTIFICATION_HUB_FROM NOTIFICATION_HUB_OAUTH_TOKEN_URL NOTIFICATION_HUB_OAUTH_CLIENT_ID NOTIFICATION_HUB_OAUTH_CLIENT_SECRET
export MINIO_ENDPOINT MINIO_REGION IMPACTC_MEDIA_BUCKET IMPACTC_MOBILE_RELEASES_BUCKET
vault_exec 'vault status' >/dev/null || fail "Vault is sealed or unavailable"
vault_exec "vault secrets list | grep -q '^secret/'" \
  || fail "KV v2 engine 'secret/' is not enabled; follow docs/VAULT.md first"

mc_config="$(mktemp -d)"
cleanup() {
  rm -rf "$mc_config"
}
trap cleanup EXIT

mc() {
  docker run --rm \
    --network optimizesolux-common \
    -v "$mc_config:/root/.mc" \
    -v "$POLICY_DIR:/policies:ro" \
    "$MC_IMAGE" "$@"
}

printf '%s\n' '[1/4] Configuring isolated MinIO buckets and identities...'
mc alias set "$MINIO_ALIAS" "$MINIO_ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" --api S3v4
mc mb --ignore-existing "${MINIO_ALIAS}/${IMPACTC_MEDIA_BUCKET}"
mc mb --ignore-existing "${MINIO_ALIAS}/${IMPACTC_MOBILE_RELEASES_BUCKET}"
mc anonymous set none "${MINIO_ALIAS}/${IMPACTC_MEDIA_BUCKET}"
mc anonymous set none "${MINIO_ALIAS}/${IMPACTC_MOBILE_RELEASES_BUCKET}"
mc admin policy create "$MINIO_ALIAS" impactc-media-rw /policies/impactc-media-rw.json
mc admin policy create "$MINIO_ALIAS" impactc-mobile-releases-write /policies/impactc-mobile-releases-write.json
mc admin user add "$MINIO_ALIAS" "$IMPACTC_S3_ACCESS_KEY" "$IMPACTC_S3_SECRET_KEY"
mc admin policy attach "$MINIO_ALIAS" impactc-media-rw --user "$IMPACTC_S3_ACCESS_KEY"
mc admin user add "$MINIO_ALIAS" "$IMPACTC_RELEASES_ACCESS_KEY" "$IMPACTC_RELEASES_SECRET_KEY"
mc admin policy attach "$MINIO_ALIAS" impactc-mobile-releases-write --user "$IMPACTC_RELEASES_ACCESS_KEY"

printf '%s\n' '[2/4] Writing ImpactC secrets to Vault...'
vault_exec 'vault kv put secret/optimizesolux/impactc/db host=impactc-db port=5432 database=impactc username="$IMPACTC_DB_USER" password="$IMPACTC_DB_PASSWORD"'
vault_exec 'vault kv put secret/optimizesolux/impactc/auth jwt_access_secret="$IMPACTC_JWT_ACCESS_SECRET" jwt_refresh_secret="$IMPACTC_JWT_REFRESH_SECRET" chat_encryption_key="$IMPACTC_CHAT_ENCRYPTION_KEY"'
vault_exec 'vault kv put secret/optimizesolux/impactc/redis host=redis port=6379 password="$IMPACTC_REDIS_PASSWORD" database=6 bullmq_prefix=impactc'
vault_exec 'vault kv put secret/optimizesolux/impactc/s3 endpoint="$MINIO_ENDPOINT" region="$MINIO_REGION" media_bucket="$IMPACTC_MEDIA_BUCKET" media_access_key="$IMPACTC_S3_ACCESS_KEY" media_secret_key="$IMPACTC_S3_SECRET_KEY" releases_bucket="$IMPACTC_MOBILE_RELEASES_BUCKET" releases_access_key="$IMPACTC_RELEASES_ACCESS_KEY" releases_secret_key="$IMPACTC_RELEASES_SECRET_KEY"'
vault_exec 'vault kv put secret/optimizesolux/impactc/oidc issuer="$IMPACTC_KEYCLOAK_ISSUER" audience="$IMPACTC_KEYCLOAK_AUDIENCE"'
vault_exec 'vault kv put secret/optimizesolux/impactc/notification-hub enabled=true base_url="$NOTIFICATION_HUB_BASE_URL" tenant_id=impactc app_id=impactc from="$NOTIFICATION_HUB_FROM" oauth_token_url="$NOTIFICATION_HUB_OAUTH_TOKEN_URL" oauth_client_id="$NOTIFICATION_HUB_OAUTH_CLIENT_ID" oauth_client_secret="$NOTIFICATION_HUB_OAUTH_CLIENT_SECRET"'

printf '%s\n' '[3/4] Creating the least-privilege ImpactC AppRole...'
vault_exec 'vault policy write impactc-read /vault/policies/impactc-read.hcl'
vault_exec "vault auth list | grep -q '^approle/'" \
  || vault_exec 'vault auth enable approle'
vault_exec 'vault write auth/approle/role/impactc token_policies=impactc-read token_ttl=1h token_max_ttl=4h'

bootstrap_dir="${COMMON_INFRA_ROOT}/private/impactc"
install -d -m 0700 "$bootstrap_dir"
role_id="$(vault_exec 'vault read -field=role_id auth/approle/role/impactc/role-id')"
secret_id="$(vault_exec 'vault write -f -field=secret_id auth/approle/role/impactc/secret-id')"
cat > "${bootstrap_dir}/approle.env" <<EOF
VAULT_ADDR=http://vault:8200
VAULT_ROLE_ID=${role_id}
VAULT_SECRET_ID=${secret_id}
EOF
chmod 0600 "${bootstrap_dir}/approle.env"

printf '%s\n' '[4/4] Verifying access boundaries...'
mc admin user info "$MINIO_ALIAS" "$IMPACTC_S3_ACCESS_KEY" >/dev/null
mc admin user info "$MINIO_ALIAS" "$IMPACTC_RELEASES_ACCESS_KEY" >/dev/null
vault_exec 'vault kv get secret/optimizesolux/impactc/db' >/dev/null

cat <<EOF
ImpactC P2 provisioning complete.
- Private buckets: ${IMPACTC_MEDIA_BUCKET}, ${IMPACTC_MOBILE_RELEASES_BUCKET}
- Vault paths: secret/data/optimizesolux/impactc/{db,auth,redis,s3,oidc,notification-hub}
- AppRole bootstrap file: ${bootstrap_dir}/approle.env (mode 0600)

Copy secret values into /opt/optimizesolux/impactc/.env only through the P3 deployment procedure.
Do not commit the AppRole bootstrap file or any generated product environment file.
EOF
