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

| UID | Title |
|-----|--------|
| `oci-targets` | Scrape targets UP/DOWN |
| `oci-vps-host` | Contabo VPS host (node-exporter) |
| `oci-docker-containers` | All containers (cAdvisor) |
| `oci-common-overview` | Redis / MinIO / Keycloak / Artemis / OTel |
| `oci-logs-containers` | Loki logs by compose project/service |

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

App-level metrics/traces require the SDK + env vars above.

## Artemis metrics

Compose runs `prepare-artemis.sh` before the stock `/docker-run.sh`:

- Installs the vendored Prometheus plugin when present
- **Strips** a broken `<metrics>` block if the JAR is missing (recovers Contabo
  crash loops that left Prometheus with `lookup artemis … server misbehaving`)

After deploy, `artemis` must be **Up** (not Restarting). Then Prometheus
`http://artemis:8161/metrics` can go green once the plugin is registered.

```bash
sudo /opt/optimizesolux/common-infra/install.sh --force-update artemis
docker ps --filter name=artemis
docker logs optimizesolux-common-artemis-1 --tail 80
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

1. Confirm targets: `https://prometheus.optimizesolux.com/targets` — `cadvisor` must be UP.
2. Quick check from the VPS:
   ```bash
   docker exec optimizesolux-common-prometheus-1 wget -qO- http://cadvisor:8080/metrics | head
   docker exec optimizesolux-common-prometheus-1 wget -qO- 'http://localhost:9090/api/v1/query?query=container_memory_working_set_bytes' | head -c 500
   ```
3. Recreate collectors after sync:
   ```bash
   sudo /opt/optimizesolux/common-infra/install.sh --force-update cadvisor
   sudo /opt/optimizesolux/common-infra/install.sh --force-update prometheus
   sudo /opt/optimizesolux/common-infra/install.sh --force-update grafana
   sudo /opt/optimizesolux/common-infra/install.sh --force-update otel
   sudo /opt/optimizesolux/common-infra/install.sh --force-update artemis
   ```

## Follow-ups (out of this repo)

- **Traefik metrics**: enable Prometheus entrypoint in `shared-traefik` and add a
  scrape job if the metrics port is reachable from `optimizesolux-common`.
- **Alertmanager**: not deployed yet.

## K8s mirror

`k8s/base/observability.yaml` mirrors scrapes + cAdvisor DaemonSet + redis-exporter.
Contabo production path remains Docker Compose.
