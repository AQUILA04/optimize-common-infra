#!/usr/bin/env bash
# Safe Artemis prep before stock /docker-run.sh:
# - Install Prometheus plugin when artifacts are present
# - Strip metrics config if plugin JAR is missing (recovers crash loops)
# Always exits 0 so the broker can start.
set +e

INSTANCE="${ARTEMIS_INSTANCE:-/var/lib/artemis-instance}"
ETC="${INSTANCE}/etc"
BROKER="${ETC}/broker.xml"
BOOTSTRAP="${ETC}/bootstrap.xml"
LIB_DIR="${INSTANCE}/lib"
WEB_DIR="${INSTANCE}/web"
PLUGIN_SRC="${ARTEMIS_PLUGIN_SRC:-/opt/oci-artemis-plugins}"
PLUGIN_VER="${ARTEMIS_PROMETHEUS_PLUGIN_VERSION:-3.1.0}"
PLUGIN_JAR="artemis-prometheus-metrics-plugin-${PLUGIN_VER}.jar"
PLUGIN_CLASS="org.apache.activemq.artemis.core.server.metrics.plugins.ArtemisPrometheusMetricsPlugin"

strip_metrics() {
  if [[ -f "${BROKER}" ]] && grep -q "ArtemisPrometheusMetricsPlugin\|<metrics>" "${BROKER}"; then
    tmp="$(mktemp)"
    awk '
      BEGIN { skip=0 }
      /<metrics>/ { skip=1; next }
      /<\/metrics>/ { skip=0; next }
      skip { next }
      { print }
    ' "${BROKER}" > "${tmp}" && mv "${tmp}" "${BROKER}"
    echo "prepare-artemis: stripped <metrics> from broker.xml"
  fi
  if [[ -f "${BOOTSTRAP}" ]] && grep -q 'url="metrics"' "${BOOTSTRAP}"; then
    tmp="$(mktemp)"
    grep -v 'url="metrics"' "${BOOTSTRAP}" > "${tmp}" && mv "${tmp}" "${BOOTSTRAP}"
    echo "prepare-artemis: removed metrics app from bootstrap.xml"
  fi
}

if [[ ! -f "${BROKER}" ]]; then
  echo "prepare-artemis: no broker.xml yet (first create) — skip"
  exit 0
fi

mkdir -p "${LIB_DIR}" "${WEB_DIR}"

# Install vendored artifacts when available
if [[ -f "${PLUGIN_SRC}/${PLUGIN_JAR}" ]]; then
  cp -f "${PLUGIN_SRC}/${PLUGIN_JAR}" "${LIB_DIR}/${PLUGIN_JAR}" 2>/dev/null \
    || cp -f "${PLUGIN_SRC}/${PLUGIN_JAR}" "${LIB_DIR}/${PLUGIN_JAR}"
  echo "prepare-artemis: installed ${PLUGIN_JAR}"
fi
if [[ -f "${PLUGIN_SRC}/metrics.war" ]]; then
  cp -f "${PLUGIN_SRC}/metrics.war" "${WEB_DIR}/metrics.war" 2>/dev/null || true
  echo "prepare-artemis: installed metrics.war"
fi

if [[ ! -f "${LIB_DIR}/${PLUGIN_JAR}" ]]; then
  echo "prepare-artemis: plugin JAR missing — ensuring broker.xml has no metrics plugin"
  strip_metrics
  exit 0
fi

# Inject metrics plugin once
if ! grep -q "ArtemisPrometheusMetricsPlugin" "${BROKER}"; then
  if grep -q "</core>" "${BROKER}"; then
    tmp="$(mktemp)"
    awk -v plugin="${PLUGIN_CLASS}" '
      /<\/core>/ && !done {
        print "   <metrics>"
        print "      <jvm-gc>true</jvm-gc>"
        print "      <jvm-memory>true</jvm-memory>"
        print "      <jvm-threads>true</jvm-threads>"
        print "      <plugin class-name=\"" plugin "\"/>"
        print "   </metrics>"
        done=1
      }
      { print }
    ' "${BROKER}" > "${tmp}" && mv "${tmp}" "${BROKER}"
    echo "prepare-artemis: injected metrics plugin into broker.xml"
  fi
fi

if [[ -f "${WEB_DIR}/metrics.war" && -f "${BOOTSTRAP}" ]] && ! grep -q 'url="metrics"' "${BOOTSTRAP}"; then
  if grep -q "</web>" "${BOOTSTRAP}"; then
    tmp="$(mktemp)"
    awk '
      /<\/web>/ && !done {
        print "         <app url=\"metrics\" war=\"metrics.war\"/>"
        done=1
      }
      { print }
    ' "${BOOTSTRAP}" > "${tmp}" && mv "${tmp}" "${BOOTSTRAP}"
    echo "prepare-artemis: registered metrics app in bootstrap.xml"
  fi
fi

exit 0
