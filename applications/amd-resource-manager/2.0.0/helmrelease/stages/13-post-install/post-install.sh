#!/bin/sh
#
# Stage 13 — Installation summary
#
# Runs after every functional stage and the AIRM agent are Ready. It checks that
# the login Secrets exist and are populated, then prints the access URLs and the
# commands that retrieve the login credentials. Usernames and passwords are never
# written to the Job log.
set -eu

log() {
  printf '[airm-post-install] %s\n' "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

[ -n "$DOMAIN" ] || fail "DOMAIN is empty"

airm_user="$(kubectl get secret airm-user-credentials \
  -n "$AIRM_NAMESPACE" -o jsonpath='{.data.USER_EMAIL}' | base64 -d)"
airm_password="$(kubectl get secret airm-user-credentials \
  -n "$AIRM_NAMESPACE" -o jsonpath='{.data.USER_PASSWORD}' | base64 -d)"
keycloak_user="$(kubectl get secret keycloak-kcadmin \
  -n "$KEYCLOAK_NAMESPACE" -o jsonpath='{.data.username}' | base64 -d)"
keycloak_password="$(kubectl get secret keycloak-kcadmin \
  -n "$KEYCLOAK_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)"
[ -n "$airm_user" ] || fail "AIRM username is empty"
[ -n "$airm_password" ] || fail "AIRM password is empty"
[ -n "$keycloak_user" ] || fail "Keycloak username is empty"
[ -n "$keycloak_password" ] || fail "Keycloak password is empty"

cat <<EOF
================================================================
  AMD AI Resource Manager — Installation Complete
================================================================

  Domain:  $DOMAIN
  Gateway: $GATEWAY_NAME

  Access URLs:
    AIRM UI:  https://airmui.$DOMAIN
    AIRM API: https://airmapi.$DOMAIN
    Keycloak: https://kc.$DOMAIN

  Credentials are stored in Kubernetes Secrets and are not printed here.
  Retrieve the AIRM UI username and password:
    kubectl get secret airm-user-credentials -n $AIRM_NAMESPACE -o jsonpath='{.data.USER_EMAIL}' | base64 -d; echo
    kubectl get secret airm-user-credentials -n $AIRM_NAMESPACE -o jsonpath='{.data.USER_PASSWORD}' | base64 -d; echo

  Retrieve the Keycloak administrator username and password:
    kubectl get secret keycloak-kcadmin -n $KEYCLOAK_NAMESPACE -o jsonpath='{.data.username}' | base64 -d; echo
    kubectl get secret keycloak-kcadmin -n $KEYCLOAK_NAMESPACE -o jsonpath='{.data.password}' | base64 -d; echo

  IMPORTANT:
    - The TLS certificate is self-signed; browsers will show a warning.
================================================================
EOF
