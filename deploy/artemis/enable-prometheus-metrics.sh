#!/usr/bin/env bash
# Manual helper (same logic as prepare-artemis.sh). Prefer compose entrypoint.
exec /prepare-artemis.sh "$@" 2>/dev/null || {
  # Fallback when not mounted at /prepare-artemis.sh
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  # shellcheck source=/dev/null
  exec bash "${SCRIPT_DIR}/prepare-artemis.sh" "$@"
}
