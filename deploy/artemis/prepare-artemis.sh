#!/usr/bin/env bash
# Always strip Prometheus metrics plugin/war registration from an Artemis instance.
# The rh-messaging plugin on upstream apache/activemq-artemis is unreliable
# (ClassNotFound with wrong FQCN, then /metrics 404 when Micrometer registry
# is not visible to the webapp). Broker health is covered by cAdvisor instead.
# Always exits 0.
set +e

INSTANCE="${ARTEMIS_INSTANCE:-/var/lib/artemis-instance}"
ETC="${INSTANCE}/etc"
BROKER="${ETC}/broker.xml"
BOOTSTRAP="${ETC}/bootstrap.xml"

if [[ ! -f "${BROKER}" ]]; then
  echo "prepare-artemis: no broker.xml yet — skip"
  exit 0
fi

if grep -qE 'ArtemisPrometheusMetricsPlugin|<metrics>' "${BROKER}" 2>/dev/null; then
  tmp="$(mktemp)"
  awk '
    BEGIN { skip=0 }
    /<metrics>/ { skip=1; next }
    /<\/metrics>/ { skip=0; next }
    skip { next }
    { print }
  ' "${BROKER}" > "${tmp}" && mv "${tmp}" "${BROKER}"
  echo "prepare-artemis: stripped <metrics> from broker.xml (use cAdvisor for container metrics)"
fi

if [[ -f "${BOOTSTRAP}" ]] && grep -q 'url="metrics"' "${BOOTSTRAP}"; then
  tmp="$(mktemp)"
  grep -v 'url="metrics"' "${BOOTSTRAP}" > "${tmp}" && mv "${tmp}" "${BOOTSTRAP}"
  echo "prepare-artemis: removed metrics app from bootstrap.xml"
fi

# Remove war copy if present (optional cleanup)
rm -f "${INSTANCE}/web/metrics.war" 2>/dev/null || true

exit 0
