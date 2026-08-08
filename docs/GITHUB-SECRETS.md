# GitHub Secrets — Optimize Common Infra Contabo CD

| Secret | Example |
|--------|---------|
| `SSH_PRIVATE_KEY` | Contabo deploy key |
| `PROD_SERVER_HOST` | `169.58.127.90` |
| `PROD_SERVER_USER` | `root` |
| `GHCR_USERNAME` | GitHub user |
| `GHCR_TOKEN` | PAT `read:packages` |

Also create Actions environment **`prod`**.

## DNS (grey cloud → VPS)

`auth`, `vault`, `grafana`, `prometheus`, `mail`, `pgadmin`, `s3`, `s3-console`, `artemis`, `eureka`, `gateway`, (+ `rabbitmq` / `jaeger` if enabled).

Product hosts remain managed by each product repo.
