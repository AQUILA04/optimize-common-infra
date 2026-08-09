#!/usr/bin/env bash
# Deprecated: use prepare-artemis.sh (strip-only). Kept as a thin alias.
exec bash "$(dirname "$0")/prepare-artemis.sh" "$@"
