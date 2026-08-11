# Vault — Optimize Common Infra

## Model

- Storage: **file** under `/opt/optimizesolux/common-infra/vault/data`
- UI/API: `https://vault.optimizesolux.com` (Traefik) and `http://vault:8200` on `optimizesolux-common`
- **Dev mode is forbidden** on Contabo

## First init (once)

```bash
docker compose -f /opt/optimizesolux/common-infra/docker-compose.yml \
  --project-name optimizesolux-common --env-file /opt/optimizesolux/common-infra/.env \
  --profile core exec -T vault vault operator init -key-shares=5 -key-threshold=3 \
  -format=json > /opt/optimizesolux/common-infra/vault/keys/init.json

chmod 600 /opt/optimizesolux/common-infra/vault/keys/init.json
```

Unseal (need 3 keys):

```bash
vault operator unseal <key1>
vault operator unseal <key2>
vault operator unseal <key3>
```

Login with root token from `init.json`, then:

```bash
vault secrets enable -path=secret kv-v2
vault policy write product-read /vault/policies/product-read.hcl
vault policy write ops-admin /vault/policies/ops-admin.hcl
```

## Path convention

```text
secret/data/optimizesolux/{slug}/db
secret/data/optimizesolux/{slug}/oidc
secret/data/optimizesolux/{slug}/smtp
```

## AppRole (products)

```bash
vault auth enable approle
vault write auth/approle/role/notification-hub \
  token_policies=product-read \
  token_ttl=1h token_max_ttl=4h
```

Store `role_id` / `secret_id` in the product server env (or CI secrets), never in git.

## After reboot

Vault starts **sealed**. Unseal with 3 keys before apps that depend on it.

## Troubleshooting: `permission denied` on `/vault/data`

Symptom:

```text
storage migration check error: error="open /vault/data/core/_migration: permission denied"
```

Cause: the Vault container runs as UID **100**, but `vault/data` on the host was created as root (or another user).

Fix on Contabo:

```bash
sudo chown -R 100:100 /opt/optimizesolux/common-infra/vault/data
sudo chmod 700 /opt/optimizesolux/common-infra/vault/data
docker compose -f /opt/optimizesolux/common-infra/docker-compose.yml \
  --project-name optimizesolux-common --env-file /opt/optimizesolux/common-infra/.env \
  --profile core restart vault
```

Then unseal again if needed.
