# K8s mirror of Optimize Common Infra

## Apply (prod defaults: core + observability + mesh)

```bash
./k8s/install-k8s.sh
```

## Opt-in profiles

```bash
./k8s/install-k8s.sh --enable kafka
./k8s/install-k8s.sh --enable rabbitmq --enable tracing
# Ollama NEVER by default:
./k8s/install-k8s.sh --enable ai --force-update ollama
```

## Secrets

Copy `base/secret.example.yaml` → real Secret `oci-secrets` before production.
Do not commit real passwords.

## Force update

```bash
./k8s/install-k8s.sh --force-update keycloak
./k8s/install-k8s.sh --force-update all   # excludes ollama
```
