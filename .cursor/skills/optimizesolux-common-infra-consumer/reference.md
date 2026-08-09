# Common-infra consumer — hostname reference

Source of truth: `optimize-common-infra/docs/NETWORKING.md`.

## Shared DNS on `optimizesolux-common`

| Service | Hostname | Port |
|---------|----------|------|
| Redis | `redis` | 6379 |
| Artemis | `artemis` | 61616 (core), 8161 (console) |
| Keycloak | `keycloak` | 8080 |
| Mailpit | `mailpit` | 1025 SMTP / 8025 UI |
| Vault | `vault` | 8200 |
| MinIO | `minio` | 9000 / 9001 |
| OTel | `otel-collector` | 4317 gRPC / 4318 HTTP |
| Prometheus | `prometheus` | 9090 (UI via Traefik) |
| Grafana | `grafana` | 3000 |
| cAdvisor | `cadvisor` | 8080 |
| redis-exporter | `redis-exporter` | 9121 |
| Eureka | `eureka` | 8761 |
| Gateway | `gateway` | 8080 |
| Kafka | `kafka` | 9092 (profile) |
| RabbitMQ | `rabbitmq` | 5672 (profile) |

## Public Traefik hosts (default)

| Host | Service |
|------|---------|
| `auth.optimizesolux.com` | Keycloak |
| `mail.optimizesolux.com` | Mailpit UI |
| `vault.optimizesolux.com` | Vault |
| `grafana.optimizesolux.com` | Grafana |
| `pgadmin.optimizesolux.com` | pgAdmin |
| `s3.optimizesolux.com` | MinIO API |

## VPS paths

| Stack | Path |
|-------|------|
| Common infra | `/opt/optimizesolux/common-infra/` |
| Shared Traefik | `/opt/optimizesolux/` (shared-traefik) |
| Typical product | `/opt/{product}/` e.g. `/opt/notification-hub/` |

## Install commands (ops)

```bash
sudo /opt/optimizesolux/common-infra/install.sh
sudo /opt/optimizesolux/common-infra/install.sh --force-update keycloak
```
