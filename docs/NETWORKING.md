# Networking — Optimize Common Infra

## Docker networks

| Network | Who joins | Purpose |
|---------|-----------|---------|
| `traefik-public` | shared-traefik + exposed UIs/APIs | HTTPS edge (Let's Encrypt) |
| `optimizesolux-common` | all common tools + product containers that need tools | Internal service DNS |

Create once (install.sh does this):

```bash
docker network create traefik-public          # usually already exists
docker network create optimizesolux-common
```

Product Contabo compose:

```yaml
networks:
  optimizesolux-common:
    external: true
  traefik-public:
    external: true
```

## Service DNS (Compose service name = hostname on `optimizesolux-common`)

| Service | Hostname | Internal port(s) | Public Traefik host (default `*.optimizesolux.com`) |
|---------|----------|------------------|-----------------------------------------------------|
| Vault | `vault` | `8200` | `vault.optimizesolux.com` |
| Keycloak | `keycloak` | `8080` | `auth.optimizesolux.com` |
| Keycloak DB | `keycloak-db` | `5432` | — |
| Redis | `redis` | `6379` | — |
| Artemis | `artemis` | `61616` (core), `8161` (console) | `artemis.optimizesolux.com` |
| Kafka | `kafka` | `9092` | — |
| Zookeeper | `zookeeper` | `2181` | — |
| RabbitMQ | `rabbitmq` | `5672`, mgmt `15672` | `rabbitmq.optimizesolux.com` |
| MinIO | `minio` | API `9000`, console `9001` | `s3` / `s3-console.optimizesolux.com` |
| Mailpit | `mailpit` | SMTP `1025`, UI `8025` | `mail.optimizesolux.com` |
| pgAdmin4 | `pgadmin` | `80` | `pgadmin.optimizesolux.com` |
| Eureka | `eureka` | `8761` | `eureka.optimizesolux.com` |
| Gateway | `gateway` | `8080` | `gateway.optimizesolux.com` |
| OTel Collector | `otel-collector` | `4317` gRPC, `4318` HTTP | — |
| Prometheus | `prometheus` | `9090` | `prometheus.optimizesolux.com` |
| Loki | `loki` | `3100` | — (Grafana datasource) |
| Promtail | `promtail` | — (agent) | — |
| Grafana | `grafana` | `3000` | `grafana.optimizesolux.com` |
| node-exporter | `node-exporter` | `9100` | — |
| cAdvisor | `cadvisor` | `8080` | — |
| redis-exporter | `redis-exporter` | `9121` | — |
| Jaeger | `jaeger` | UI `16686` | `jaeger.optimizesolux.com` |
| Ollama | `ollama` | `11434` | — (profile `ai` only) |

## Product env examples

```bash
REDIS_HOST=redis
REDIS_PORT=6379
ARTEMIS_BROKER_URL=tcp://artemis:61616
OIDC_ISSUER_URI=https://auth.optimizesolux.com/realms/{slug}
SMTP_HOST=mailpit
SMTP_PORT=1025
VAULT_ADDR=http://vault:8200
# or https://vault.optimizesolux.com
OTEL_SERVICE_NAME={slug}-api
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_RESOURCE_ATTRIBUTES=service.namespace=optimizesolux,deployment.environment=prod
MINIO_ENDPOINT=http://minio:9000
```

Observability details: [OBSERVABILITY.md](./OBSERVABILITY.md).

## Application databases (per product)

Attach the product Postgres to `optimizesolux-common` with a stable hostname
`{slug}-db` (e.g. `notification-hub-db`, `cleantrack-db`) so pgAdmin can reach it.
Do **not** publish Postgres on the host; keep it internal.

## Redis isolation

| Product slug | Suggested Redis DB index | Key prefix |
|--------------|--------------------------|------------|
| cleantrack | `0` | `cleantrack:` |
| notification-hub | `1` | `nhub:` |
| elykia | `2` | `elykia:` |
| landreg | `3` | `landreg:` |
| omnishop | `4` | `omnishop:` |
| mqms | `5` | `mqms:` |
| ehealth | `6` | `ehealth:` |

## Communication flow

```text
Internet → shared-traefik (:443) → product FE/API  (traefik-public)
                                 → Keycloak / Grafana / MinIO / … (traefik-public)

Product API ──optimizesolux-common──► redis:6379
                                    ► artemis:61616
                                    ► keycloak:8080  (or public issuer URL for JWT)
                                    ► mailpit:1025
                                    ► vault:8200
                                    ► otel-collector:4318
                                    ► minio:9000

Host agents (profile observability): node-exporter, cAdvisor, Promtail → Prometheus / Loki → Grafana.
```
