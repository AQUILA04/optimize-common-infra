# Observability — Contabo / common-infra

Source of truth for the shared monitoring stack. Deployed via Compose profile
`observability` (enabled by default on Contabo through `install.sh`).

## Architecture

| Component | Role |
|-----------|------|
| **node-exporter** | Host CPU / RAM / disk / network |
| **cAdvisor** | All Docker containers on the VPS (common-infra + products + Traefik) |
| **redis-exporter** | Redis metrics |
| **Prometheus** | Scrapes exporters + MinIO + Keycloak + Artemis + OTel `:8889` |
| **otel-collector** | OTLP ingest (`4317` gRPC / `4318` HTTP) → Prometheus metrics |
| **Loki + Promtail** | Container logs via Docker socket (labels `compose_project` / `compose_service`) |
| **Grafana** | UI at `https://grafana.optimizesolux.com` (folder **OptimizeSolux**) |

```text
Products ──OTLP──► otel-collector:4318 ──► Prometheus :8889
Docker host ──────► cAdvisor / node-exporter / Promtail
Common tools ─────► Prometheus (redis-exporter, minio, keycloak, artemis)
Prometheus + Loki ► Grafana
```

## IaC layout

```text
deploy/observability/
  prometheus.yml
  otel-collector-config.yaml
  promtail-config.yml
  grafana/
    datasources/datasources.yml
    dashboards/dashboards.yml
    dashboards/json/*.json
deploy/artemis/
  enable-prometheus-metrics.sh
  plugins/          # vendored Prometheus plugin JAR + metrics.war
```

Re-apply after sync:

```bash
sudo /opt/optimizesolux/common-infra/install.sh --force-update all
# or targeted:
sudo /opt/optimizesolux/common-infra/install.sh --force-update cadvisor
sudo /opt/optimizesolux/common-infra/install.sh --force-update prometheus
sudo /opt/optimizesolux/common-infra/install.sh --force-update grafana
sudo /opt/optimizesolux/common-infra/install.sh --force-update artemis
```

## Provisioned Grafana dashboards

| UID | Title | Folder |
|-----|--------|--------|
| `oci-targets` | Scrape targets UP/DOWN | OptimizeSolux |
| `oci-vps-host` | Contabo VPS host (node-exporter) | OptimizeSolux |
| `oci-docker-containers` | All containers (cAdvisor) | OptimizeSolux |
| `oci-common-overview` | Redis / MinIO / Keycloak / Artemis / OTel | OptimizeSolux |
| `oci-logs-containers` | Loki logs by compose project/service | OptimizeSolux |
| `elykia-business-overview` | ELYKIA business Micrometer metrics | Elykia |

## Product contract (OTLP)

Products **must not** ship their own Prometheus/Grafana/Loki on Contabo.
Attach the API/workers to `optimizesolux-common` and export telemetry:

```bash
OTEL_SERVICE_NAME={slug}-api
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_RESOURCE_ATTRIBUTES=service.namespace=optimizesolux,deployment.environment=prod
```

Optional gRPC: `http://otel-collector:4317` with `OTEL_EXPORTER_OTLP_PROTOCOL=grpc`.

Without any product change you already get:

- Container CPU/RAM/network in **Docker containers** (cAdvisor)
- Stdout/stderr in **Container logs** (Promtail → Loki)

### Elykia business metrics

Prometheus scrapes `elykia-backend:8080/actuator/prometheus` on `optimizesolux-common`
(job `elykia-backend` in `deploy/observability/prometheus.yml`). The Contabo compose
must publish the API container as hostname `elykia-backend`.

**Provisioned automatically** (no manual import):

| Artefact | Path |
|----------|------|
| Dashboard **ELYKIA - Business Overview** | Grafana folder **Elykia** (`deploy/observability/grafana/dashboards/elykia/`) |
| Alert rules (credit / stock / tontine / …) | `deploy/observability/grafana/alerting/alertrules.yml` |
| Contact point email | `contactpoints.yml` → `${ALERT_EMAIL_TO}` (default `alert@optimizesolux.com`) |

After syncing this repo on Contabo:

```bash
sudo /opt/optimizesolux/common-infra/install.sh --force-update prometheus
sudo /opt/optimizesolux/common-infra/install.sh --force-update grafana
# Target UP?
docker exec optimizesolux-common-prometheus-1 wget -qO- 'http://localhost:9090/api/v1/targets' | grep -A2 elykia-backend
```

**Email alerts (Resend = same SMTP as notification-hub)** — in `/opt/optimizesolux/common-infra/.env`:

```bash
ALERT_EMAIL_TO=alert@optimizesolux.com
GF_SMTP_ENABLED=true
GF_SMTP_HOST=smtp.resend.com:465
GF_SMTP_USER=resend
GF_SMTP_PASSWORD=<MAIL_PASS from /opt/notification-hub/prod/.env>
GF_SMTP_FROM_ADDRESS=noreply@optimizesolux.com
GF_SMTP_FROM_NAME=OptimizeSolux Grafana
GF_SMTP_STARTTLS_POLICY=NoStartTLS
```

Then `install.sh --force-update grafana`. Do not commit secrets; copy `MAIL_PASS` from notification-hub only on the VPS.

Do **not** run ELYKIA’s product `deploy/monitoring` stack on Contabo (legacy DigitalOcean only).

App-level metrics/traces also use the SDK + OTEL env vars above.

## Artemis metrics

Broker-level Prometheus (`http://artemis:8161/metrics`) is **not** enabled on the
upstream `apache/activemq-artemis` image: the rh-messaging plugin either fails to
load or serves `/metrics` as HTTP 404 (Micrometer registry not visible to the war).

`prepare-artemis.sh` **strips** any leftover `<metrics>` / metrics app so the broker
stays up after earlier experiments.

Monitor Artemis via the **Docker containers** dashboard (cAdvisor): CPU/RAM/network
of `optimizesolux-common-artemis-1`.

Plugin JARs under `deploy/artemis/plugins/` are kept for a possible future custom
image; they are not auto-wired into Contabo Compose.

```bash
sudo /opt/optimizesolux/common-infra/install.sh --force-update artemis
sudo /opt/optimizesolux/common-infra/install.sh --force-update prometheus
docker ps --filter name=artemis
```

## Traces / Jaeger (opt-in)

Default OTel traces/logs pipelines use the `debug` exporter (no Jaeger dependency).

To enable UI traces:

```bash
sudo /opt/optimizesolux/common-infra/install.sh --enable tracing
```

Then point the collector traces exporter at Jaeger OTLP (`jaeger:4317`) by updating
`deploy/observability/otel-collector-config.yaml` (add an `otlp` exporter to
`jaeger:4317` and set the traces pipeline exporter), then:

```bash
sudo /opt/optimizesolux/common-infra/install.sh --force-update otel
```

Jaeger UI: `https://jaeger.optimizesolux.com`.

## Troubleshooting Grafana "No data" (Docker containers)

Logs (Loki) can work while this dashboard is empty: Promtail reads Docker logs;
container CPU/RAM need **cAdvisor → Prometheus**.

1. Targets: `https://prometheus.optimizesolux.com/targets` — job `cadvisor` UP.
2. In Grafana Explore (Prometheus), run:
   ```promql
   count({__name__=~"container_.*", job="cadvisor"})
   container_memory_working_set_bytes{job="cadvisor", id!="/"}
   ```
   If the first query is 0, cAdvisor is not exporting container series (Docker/containerd
   mounts). If it returns series but the dashboard is empty, force-update Grafana.
3. Recreate:
   ```bash
   sudo /opt/optimizesolux/common-infra/install.sh --force-update cadvisor
   sudo /opt/optimizesolux/common-infra/install.sh --force-update prometheus
   sudo /opt/optimizesolux/common-infra/install.sh --force-update grafana
   ```

## Follow-ups (out of this repo)

- **Traefik metrics**: enable Prometheus entrypoint in `shared-traefik` and add a
  scrape job if the metrics port is reachable from `optimizesolux-common`.
- **Alertmanager**: not deployed yet.

## K8s mirror

`k8s/base/observability.yaml` mirrors scrapes + cAdvisor DaemonSet + redis-exporter.
Contabo production path remains Docker Compose.
