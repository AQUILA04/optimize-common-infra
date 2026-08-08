FROM quay.io/keycloak/keycloak:26.2.5

USER root
COPY themes/ /opt/keycloak/themes/
# Realms are mounted at runtime from ./images/keycloak/realms (or baked optionally)
COPY realms/ /opt/keycloak/data/import/

USER 1000

ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_HTTP_ENABLED=true

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start", "--import-realm"]
