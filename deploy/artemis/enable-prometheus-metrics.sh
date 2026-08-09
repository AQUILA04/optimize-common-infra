#!/usr/bin/env bash
# Idempotent: enable Artemis Prometheus metrics plugin + /metrics servlet.
# Runs inside apache/activemq-artemis before `artemis run`.
# Plugin artifacts are mounted from deploy/artemis/plugins (vendored in git).
set -euo pipefail

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

if [[ ! -f "${BROKER}" ]]; then
  echo "enable-prometheus-metrics: ${BROKER} missing, skip" >&2
  exit 0
fi

mkdir -p "${LIB_DIR}" "${WEB_DIR}"

if [[ -f "${PLUGIN_SRC}/${PLUGIN_JAR}" ]]; then
  cp -f "${PLUGIN_SRC}/${PLUGIN_JAR}" "${LIB_DIR}/${PLUGIN_JAR}"
  echo "enable-prometheus-metrics: installed ${PLUGIN_JAR}"
fi
if [[ -f "${PLUGIN_SRC}/metrics.war" ]]; then
  cp -f "${PLUGIN_SRC}/metrics.war" "${WEB_DIR}/metrics.war"
  echo "enable-prometheus-metrics: installed metrics.war"
fi

# Ensure metrics plugin block in broker.xml
if [[ -f "${LIB_DIR}/${PLUGIN_JAR}" ]] && ! grep -q "ArtemisPrometheusMetricsPlugin" "${BROKER}"; then
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
    ' "${BROKER}" > "${tmp}"
    mv "${tmp}" "${BROKER}"
    echo "enable-prometheus-metrics: injected metrics plugin into broker.xml"
  else
    echo "enable-prometheus-metrics: could not find </core> in broker.xml" >&2
  fi
fi

# Register metrics app in bootstrap.xml when war exists
if [[ -f "${WEB_DIR}/metrics.war" && -f "${BOOTSTRAP}" ]]; then
  if ! grep -q 'url="metrics"' "${BOOTSTRAP}"; then
    if grep -q "</web>" "${BOOTSTRAP}"; then
      tmp="$(mktemp)"
      awk '
        /<\/web>/ && !done {
          print "         <app url=\"metrics\" war=\"metrics.war\"/>"
          done=1
        }
        { print }
      ' "${BOOTSTRAP}" > "${tmp}"
      mv "${tmp}" "${BOOTSTRAP}"
      echo "enable-prometheus-metrics: registered metrics app in bootstrap.xml"
    fi
  fi
fi
