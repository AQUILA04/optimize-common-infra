# Migration checklist — products → common-infra

## Prerequisites

1. `shared-traefik` running (`traefik-public` exists).
2. Common stack installed: `sudo /opt/optimizesolux/common-infra/install.sh`
3. Secrets filled in `/opt/optimizesolux/common-infra/.env`
4. Vault initialized ([VAULT.md](./VAULT.md))
5. DNS for tool hosts + product hosts (grey cloud)

## Per product

| Step | Action |
|------|--------|
| 1 | Branch Contabo compose: keep API/FE/`{slug}-db` only |
| 2 | Join `optimizesolux-common` + `traefik-public` |
| 3 | Point env to shared hostnames ([CONSUMER-GUIDE.md](./CONSUMER-GUIDE.md)) |
| 4 | Maildev → Mailpit (`SMTP_HOST=mailpit`) |
| 5 | Move realm JSON → `images/keycloak/realms/{slug}-realm.json` |
| 6 | Store client secrets in Vault `secret/optimizesolux/{slug}/…` |
| 7 | Remove local monitoring / pgAdmin / MinIO / brokers from product compose |
| 8 | Smoke: login Keycloak realm, Redis ping, SMTP to Mailpit UI, health API |

## Product inventory (initial)

| Product | Remove from Contabo compose | Notes |
|---------|----------------------------|-------|
| notification-hub | redis, artemis, keycloak, mailpit | Keep postgres app |
| clean-track-pro | redis, keycloak, maildev | Keep postgres; SMTP prod → Resend |
| elykia | minio, monitoring stack, pgadmin tools | Keep db; MinIO → shared |
| landreg | keycloak, kafka, zookeeper | Keep postgres + mongodb métier |
| omnishop | redis, keycloak, maildev | Keep postgres |
| mqms* | redis, keycloak, kafka/zk, pgadmin | Keep app DB |

## Rollback

Re-enable previous product compose profiles/services and detach from `optimizesolux-common` if needed.
Common stack can stay running (idempotent).
