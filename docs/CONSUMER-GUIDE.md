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
| OTel | `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318` |
| MinIO | `MINIO_ENDPOINT=http://minio:9000` |
| Eureka | `EUREKA_CLIENT_SERVICEURL_DEFAULTZONE=http://eureka:8761/eureka/` |

Redis DB index / key prefix: see [NETWORKING.md](./NETWORKING.md).

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

- Redis, Keycloak, Artemis/Kafka, MinIO, Maildev/Mailpit
- Local Prometheus/Grafana/Loki/pgAdmin stacks

**Keep:** API, frontend, **métier DB**.

## 5. Keycloak realm

Add/update realm JSON under `images/keycloak/realms/` in this repo.
Rebuild Keycloak image via CI, then:

```bash
sudo /opt/optimizesolux/common-infra/install.sh --force-update keycloak
```

## 6. DNS (grey cloud)

Product hosts still point to the Contabo VPS IP.
Shared tool UIs: `auth`, `vault`, `grafana`, `mail`, `pgadmin`, `s3`, …
