# Optimize Common Infra — functional spec
#
# Source of truth for scope decisions. Networking details: NETWORKING.md

## Problem

Each OptimizeSolux product on Contabo embeds its own Keycloak, Redis, broker,
mail catcher, and monitoring stack → duplicated RAM, ports, secrets, and drift.

## Goal

One shared tools stack (`optimize-common-infra`) deployed once on the VPS via
Compose (default Contabo path) with a K8s mirror. Product compose files keep
**business artifacts + application databases** and attach to `optimizesolux-common`.

## Boundaries

| In common-infra | Per product |
|-----------------|-------------|
| Keycloak (multi-realm), Redis, Artemis | Postgres/Mongo **métier** |
| MinIO, Mailpit, Vault, pgAdmin4 | API / frontend / workers |
| OTel, Prometheus, Grafana, Loki, Promtail, node-exporter, cAdvisor, redis-exporter | Product-specific config + OTLP SDK |
| Eureka, Spring Cloud Gateway | |
| Kafka/Zookeeper, RabbitMQ, Jaeger (opt-in profiles) | |
| Ollama (**manual `--enable ai` only**) | |

## Edge

TLS reverse proxy stays in the **separate** repo `shared-traefik`.
Common-infra only joins the external network `traefik-public`.

## Deploy contract

- `install.sh` — idempotent Contabo entrypoint
- `--force-update <tool|all>` — recreate/pull targeted services (`all` excludes Ollama)
- `--enable <profile>` — kafka | rabbitmq | tracing | ai | mesh | observability | core
- `k8s/install-k8s.sh` — same catalogue via Kustomize

## Layout on VPS

`/opt/optimizesolux/common-infra/`
