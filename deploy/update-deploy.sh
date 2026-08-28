#!/usr/bin/env bash
# =============================================================================
# update-deploy.sh — Sync deploy scripts + compose from GitHub (atomic swap)
# NHUB_GITHUB_REPO / OCI_GITHUB_REPO = owner/repo (default AQUILA04/optimize-common-infra)
# =============================================================================
set -euo pipefail

REPO="${OCI_GITHUB_REPO:-${NHUB_GITHUB_REPO:-AQUILA04/optimize-common-infra}}"
ROOT="/opt/optimizesolux/common-infra"

echo ">>> [update-deploy] Fetching $REPO ..."
rm -rf /tmp/optimize-common-infra_src
git clone --depth 1 "https://github.com/${REPO}.git" /tmp/optimize-common-infra_src >/dev/null 2>&1

rm -rf "$ROOT/deploy.new"
mkdir -p "$ROOT/deploy.new"
cp -a /tmp/optimize-common-infra_src/deploy/. "$ROOT/deploy.new/"
cp -a /tmp/optimize-common-infra_src/docker-compose.yml "$ROOT/deploy.new/docker-compose.yml"
cp -a /tmp/optimize-common-infra_src/images "$ROOT/deploy.new/images" 2>/dev/null || true
cp -a /tmp/optimize-common-infra_src/install.sh "$ROOT/deploy.new/install.sh"
cp -a /tmp/optimize-common-infra_src/k8s "$ROOT/deploy.new/k8s" 2>/dev/null || true
rm -rf /tmp/optimize-common-infra_src

chmod +x "$ROOT/deploy.new"/*.sh 2>/dev/null || true
chmod +x "$ROOT/deploy.new/install.sh" 2>/dev/null || true
find "$ROOT/deploy.new" -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true

BACKUP="$ROOT/deploy.old_$(date +%s)"
if [[ -d "$ROOT/deploy" ]]; then
  mv "$ROOT/deploy" "$BACKUP"
  echo ">>> [update-deploy] Backup → $BACKUP"
fi
mv "$ROOT/deploy.new" "$ROOT/deploy"

# Keep compose + install at root for convenience
cp -a "$ROOT/deploy/docker-compose.yml" "$ROOT/docker-compose.yml"
cp -a "$ROOT/deploy/install.sh" "$ROOT/install.sh"
chmod +x "$ROOT/install.sh"
rm -rf "$ROOT/images"
cp -a "$ROOT/deploy/images" "$ROOT/images" 2>/dev/null || true

echo ">>> [update-deploy] Done."
