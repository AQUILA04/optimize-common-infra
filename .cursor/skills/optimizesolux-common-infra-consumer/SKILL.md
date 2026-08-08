---
name: optimizesolux-common-infra-consumer
description: >-
  Wire OptimizeSolux product apps to shared Contabo tools (Redis, Artemis,
  Keycloak, Mailpit, Vault, MinIO, OTel) via optimize-common-infra and
  shared-traefik. Use when creating Contabo/CD deploy for a new product,
  migrating a product off embedded redis/keycloak/broker, or attaching to
  optimizesolux-common. Keep local docker-compose autonomous for laptop dev.
---

# OptimizeSolux — Common Infra consumer (product deploy)

Canonical stack: repo `optimize-common-infra` on VPS at `/opt/optimizesolux/common-infra/`.
Edge TLS: separate repo `shared-traefik` (`traefik-public`). **Never** absorb Traefik into a product.

Read detail from that repo when available:

- `docs/CONSUMER-GUIDE.md`
- `docs/NETWORKING.md`
- `docs/MIGRATION-FROM-PRODUCTS.md`

## Hard rules

1. **Prod Contabo compose** ships only: API, frontend (or workers), **métier DB**. No redis / keycloak / artemis / kafka / minio / mailpit / grafana / pgadmin.
2. **Local compose** (`docker-compose.yml` at repo root) stays **self-contained**: postgres + redis + broker + keycloak + mail catcher so `docker compose up` works offline.
3. Product DB hostname on shared net: `{slug}-db` (alias), never published on host.
4. Join both networks on Contabo:
   - `optimizesolux-common` (external) — tools + app DB + API
   - `traefik-public` (external) — public FE/API labels
5. Keycloak realms live in `optimize-common-infra/images/keycloak/realms/{slug}-realm.json`. Rebuild Keycloak image, then `install.sh --force-update keycloak`. Product may keep a realm JSON **for local import only**.
6. OIDC issuer prod: `https://auth.optimizesolux.com/realms/{slug}` (not a per-product `*-auth` host).
7. Redis isolation: use DB index + key prefix from the table below (set `REDIS_DATABASE` / app prefix if supported).
8. Ollama / profile `ai`: never enable from product CD.

## Redis DB index

| Slug | DB | Prefix |
|------|----|--------|
| cleantrack | 0 | `cleantrack:` |
| notification-hub | 1 | `nhub:` |
| elykia | 2 | `elykia:` |
| landreg | 3 | `landreg:` |
| omnishop | 4 | `omnishop:` |
| mqms | 5 | `mqms:` |

## Prod env map

| Need | Value |
|------|--------|
| Redis | `REDIS_HOST=redis` `REDIS_PORT=6379` `REDIS_PASSWORD` (= common-infra `.env`) `REDIS_DATABASE={index}` |
| Artemis | `ARTEMIS_BROKER_URL=tcp://artemis:61616` + user/pass from common-infra |
| Kafka | `kafka:9092` (only if common profile `kafka` enabled) |
| OIDC | `OIDC_ISSUER_URI=https://auth.optimizesolux.com/realms/{slug}` |
| SMTP catcher / staging | `SMTP_HOST=mailpit` `SMTP_PORT=1025` |
| Real outbound email | product choice (e.g. Resend) — OK; do not run a second Mailpit in product compose |
| Vault | `VAULT_ADDR=http://vault:8200` |
| OTel | `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318` |
| MinIO | `MINIO_ENDPOINT=http://minio:9000` |

## Prod compose skeleton

```yaml
services:
  postgres:
    # métier only
    networks:
      optimizesolux-common:
        aliases: ["{slug}-db"]

  api:
    environment:
      REDIS_HOST: redis
      REDIS_PORT: "6379"
      REDIS_DATABASE: "{index}"
      ARTEMIS_BROKER_URL: tcp://artemis:61616
      OIDC_ISSUER_URI: https://auth.optimizesolux.com/realms/{slug}
    networks: [optimizesolux-common, traefik-public]
    # Traefik labels on traefik-public — same pattern as existing products

  frontend:
    networks: [traefik-public]

networks:
  optimizesolux-common:
    external: true
  traefik-public:
    external: true
```

Do **not** `depends_on` shared tools (they live in another compose project). Document prerequisite: common-infra already up.

## Local vs Contabo checklist

When adding or migrating deploy:

- [ ] Root `docker-compose.yml`: still starts local redis/broker/keycloak/mail + postgres
- [ ] `deploy/docker-compose.prod.yml`: only API/FE/DB; external `optimizesolux-common` + `traefik-public`
- [ ] `setup-server.sh`: ensure `optimizesolux-common` (+ `traefik-public`) exist; **do not** create product-local redis/keycloak
- [ ] `.env.prod.example` + secrets docs: OIDC → `auth.optimizesolux.com`; drop product Keycloak admin/image secrets
- [ ] CD (`init.sh` / Actions): pass Redis/Artemis passwords matching common-infra; remove Keycloak hostname/admin product secrets
- [ ] Realm: add/update in `optimize-common-infra` if new clients; keep product realm file for local only
- [ ] DNS: product FE/API A records (grey cloud). Drop product `*-auth` if migrating off embedded Keycloak
- [ ] Docs: link CONSUMER-GUIDE; note common-infra prerequisite

## New product bootstrap order

1. Confirm common-infra + shared-traefik running on VPS.
2. Add Keycloak realm in common-infra → force-update keycloak.
3. Scaffold product Contabo compose (API/FE/DB only) + CD like CleanTrack / Notification Hub.
4. Point env to shared hostnames; Redis DB index from table.
5. Smoke: JWT from `auth…/realms/{slug}`, Redis, broker, API health, FE via Traefik.

## Anti-patterns

- Second Keycloak / Redis / Artemis on Contabo for a product
- Putting tools on `traefik-public` only and skipping `optimizesolux-common`
- Publishing métier Postgres ports on the host
- Enabling Ollama from product CD
- Breaking local-only compose so laptop needs the VPS stack

## Extra reference

- Full hostname/port table: [reference.md](reference.md)
