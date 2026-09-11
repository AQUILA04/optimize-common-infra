#!/usr/bin/env bash
# Thin wrapper — full realm alignment lives in bootstrap-notification-hub-realm.sh
# Kept for backward compatibility with older install / runbooks.
set -euo pipefail
ROOT="${OCI_ROOT:-/opt/optimizesolux/common-infra}"
SCRIPT="$ROOT/deploy/bootstrap-notification-hub-realm.sh"
if [[ ! -x "$SCRIPT" && -f "$SCRIPT" ]]; then
  chmod +x "$SCRIPT"
fi
if [[ ! -f "$SCRIPT" ]]; then
  echo "Missing $SCRIPT" >&2
  exit 1
fi
exec bash "$SCRIPT"
