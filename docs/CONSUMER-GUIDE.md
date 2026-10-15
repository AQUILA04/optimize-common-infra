# How a product attaches to Optimize Common Infra

## 1. Networks (Contabo compose métier)

```yaml
networks:
  optimizesolux-common:
    external: true
  traefik-public:
    external: true
```

Attach API / workers / `{slug}-db` to `optimizesolux-common`.
Attach FE / API (public) to `traefik-public` for Traefik labels.

## 2. Environment variables

| Need | Value |
|------|--------|
| Redis | `REDIS_HOST=redis` `REDIS_PORT=6379` (+ password from Vault / `.env`) |
| Artemis | `ARTEMIS_BROKER_URL=tcp://artemis:61616` |
| Keycloak issuer | `https://auth.optimizesolux.com/realms/{slug}` |
| SMTP catcher | `SMTP_HOST=mailpit` `SMTP_PORT=1025` |
| Vault | `VAULT_ADDR=http://vault:8200` or `https://vault.optimizesolux.com` |
| OTel | See [OBSERVABILITY.md](./OBSERVABILITY.md) — `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318` |
| MinIO | `MINIO_ENDPOINT=http://minio:9000` |
| ClamAV | `CLAMAV_HOST=clamav` `CLAMAV_PORT=3310` — see [Antivirus on uploads](#antivirus-on-uploads) |
| Eureka | `EUREKA_CLIENT_SERVICEURL_DEFAULTZONE=http://eureka:8761/eureka/` |

### OTel (required for app metrics / traces)

```bash
OTEL_SERVICE_NAME={slug}-api
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_RESOURCE_ATTRIBUTES=service.namespace=optimizesolux,deployment.environment=prod
```

Container CPU/RAM and logs for product compose projects appear in Grafana automatically
(cAdvisor + Promtail) as long as containers run on the same Contabo Docker host.
Do **not** embed Prometheus/Grafana/Loki in the product Contabo compose.

Redis DB index / key prefix: see [NETWORKING.md](./NETWORKING.md).

### Antivirus on uploads

Every user-uploaded document goes through the shared `clamd` **before** it is written to MinIO or the product DB. MinIO has no antivirus hook: an object already in a bucket was never scanned.

1. Stream the bytes to `clamav:3310` with the clamd `INSTREAM` command (Java: a clamd client over TCP; Node: `clamscan` / `clamdjs` in daemon mode).
2. `stream: OK` → store the file.
3. `... FOUND` → reject the upload (HTTP 422) and store nothing.
4. Connection error, timeout, or `INSTREAM size limit exceeded` → reject the upload. Never store on scan failure.

The limit per file is `CLAMAV_MAX_SIZE` in the common-infra `.env` (default `100M`). Keep the product upload limit at or below it.
`clamd` speaks plain TCP with no authentication: call it only on `optimizesolux-common`, never through Traefik.

RestoOS convention:

- public host `https://restoos.optimizesolux.com`
- frontend + landing same-origin on `/`
- API same-origin on `/api`
- Redis DB `9`, prefix `restoos:`

## 3. Application database hostname

Expose product Postgres on `optimizesolux-common` as `{slug}-db`:

```yaml
services:
  postgres:
    container_name: notification-hub-db   # or hostname via network aliases
    networks:
      optimizesolux-common:
        aliases: ["notification-hub-db"]
```

Register that host in pgAdmin (`https://pgadmin.optimizesolux.com`).

## 4. What to remove from product Contabo compose

- Redis, Keycloak, Artemis/Kafka, MinIO, Maildev/Mailpit, ClamAV
- Local Prometheus/Grafana/Loki/pgAdmin stacks

**Keep:** API, frontend, **métier DB**.

## 5. Keycloak realm & themes

- Realm JSON: `images/keycloak/realms/{slug}-realm.json` — **seed only** (`--import-realm` creates a realm if missing; it does **not** re-apply JSON deltas on an existing realm).
- Login themes: `images/keycloak/themes/` — **mounted at runtime** on Contabo (git sync + force-update is enough; no image rebuild for theme/CSS changes).
- Custom image (`KEYCLOAK_IMAGE`) still used for base Keycloak version; realm import + themes come from synced files.
- **notification-hub** live alignment: `deploy/bootstrap-notification-hub-realm.sh` (idempotent `kcadm`) ensures roles (`notification-sender`, `notification-admin`) and clients (`notification-hub-console`, `notification-hub-api`, `biocollect-notification-sender`, `s2a`, `restoos`, `elykia`) match the JSON. Runs automatically after `install.sh --force-update keycloak`. Secrets are never rotated if already set.

### GitHub Actions CD (`workflow_dispatch`, force-update = `keycloak`)

1. Waits for **Optimize Common Infra CI** to finish if you pushed theme/realm changes (CI rebuilds the image when `images/keycloak/**` changes — optional for themes-only).
2. Run workflow **Optimize Common Infra CD** → action `install` → force-update `keycloak`.
3. CD SSHs to Contabo, runs `install.sh --force-update keycloak` (sync git + recreate container + owner / notification-hub realm bootstrap).

CD does **not** run automatically on `main` pushes — only on `release/**` after CI, or manual dispatch.

```bash
sudo /opt/optimizesolux/common-infra/install.sh --force-update keycloak
# Or align notification-hub only (no Keycloak recreate):
sudo bash /opt/optimizesolux/common-infra/deploy/bootstrap-notification-hub-realm.sh
```

## 6. DNS (Cloudflare Proxied)

Product hosts still point to the Contabo VPS IP with **Proxy enabled** (orange cloud)
and SSL mode **Full**, provided `shared-traefik` uses Cloudflare DNS-01 (`CF_DNS_API_TOKEN`).
Shared tool UIs: `auth`, `vault`, `grafana`, `mail`, `pgadmin`, `s3`, …
