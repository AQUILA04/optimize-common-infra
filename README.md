# Optimize Common Infra

Stack d’outils **partagés** OptimizeSolux pour Contabo (Docker Compose) et Kubernetes.

Les produits (CleanTrack, Notification Hub, Elykia, …) gardent leurs **bases métier** et artefacts
(API/frontend) ; ils se connectent à ce stack via le réseau Docker `optimizesolux-common`.

Edge TLS : repo séparé [`shared-traefik`](https://github.com/AQUILA04/shared-traefik) (réseau `traefik-public`).

## Quick start (Contabo)

```bash
# Sur le VPS (après clone / sync)
sudo /opt/optimizesolux/common-infra/install.sh
sudo /opt/optimizesolux/common-infra/install.sh --force-update keycloak
sudo /opt/optimizesolux/common-infra/install.sh --enable kafka
# Ollama : JAMAIS par défaut
sudo /opt/optimizesolux/common-infra/install.sh --enable ai --force-update ollama
```

## Layout serveur

```text
/opt/optimizesolux/common-infra/
  install.sh
  docker-compose.yml
  .env
  deploy/
  vault/          # unseal keys — hors git
```

## Docs

| Doc | Contenu |
|-----|---------|
| [docs/SPEC.md](docs/SPEC.md) | Spec fonctionnelle |
| [docs/NETWORKING.md](docs/NETWORKING.md) | Réseaux, hostnames, ports |
| [docs/OBSERVABILITY.md](docs/OBSERVABILITY.md) | Grafana / Prometheus / OTel / Loki (IaC) |
| [docs/CONSUMER-GUIDE.md](docs/CONSUMER-GUIDE.md) | Brancher un produit |
| [docs/MIGRATION-FROM-PRODUCTS.md](docs/MIGRATION-FROM-PRODUCTS.md) | Migrer depuis les compose produits |
| [docs/VAULT.md](docs/VAULT.md) | Bootstrap Vault |
| [docs/GITHUB-SECRETS.md](docs/GITHUB-SECRETS.md) | Secrets Actions Contabo |
| [k8s/README.md](k8s/README.md) | Install K8s idempotent |
| [`.cursor/skills/optimizesolux-common-infra-consumer`](.cursor/skills/optimizesolux-common-infra-consumer/SKILL.md) | Skill agent : brancher un produit |

## Profiles Compose

| Profile | Défaut Contabo | Services |
|---------|----------------|----------|
| `core` | oui | redis, artemis, keycloak-db, keycloak, minio, mailpit, vault, pgadmin |
| `observability` | oui | otel, prometheus, grafana, loki, promtail, node-exporter, cadvisor, redis-exporter |
| `mesh` | oui | eureka, gateway |
| `kafka` | non | zookeeper, kafka |
| `rabbitmq` | non | rabbitmq |
| `tracing` | non | jaeger |
| `ai` | **non** | ollama (activation manuelle uniquement) |

## License

Proprietary — OptimizeSolux.
