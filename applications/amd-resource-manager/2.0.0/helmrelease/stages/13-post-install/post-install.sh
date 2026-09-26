#!/bin/sh
#
# Stage 13 — Installation completion summary
#
# This script is the GitOps counterpart of installer step 12. After every
# functional stage and the agent are Ready, it reads the generated AIRM and
# Keycloak login credentials and prints the domain, access URLs, Gateway name,
# and credentials as a final installation summary.
#
# Differences from the original installer step 12:
# 1. It runs as a Flux health-gated Kubernetes Job after agent readiness rather
#    than printing from the operator's local terminal.
# 2. Missing domain or credential values are hard failures, proving that the
#    expected Secrets survived the complete install flow. The installer printed
#    fallback text when values were unavailable.
# 3. The summary is intentionally shorter: uninstall commands and intermediate
#    implementation reminders are maintained in catalog documentation rather
#    than emitted by an in-cluster workload.
# 4. Domain, namespaces, and Gateway name are supplied by catalog values rather
#    than installer globals.
#
# SECURITY NOTE: For parity with installer step 12, this implementation prints
# plaintext credentials. Unlike terminal output, Kubernetes Job logs may be
# retained, collected centrally, or readable by users with pod/log access.
# Reviewers should explicitly approve this behavior. A safer production design
# would print only the Secret names and `kubectl get secret ...` retrieval
# commands, leaving credential disclosure as an audited operator action.
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

  Credentials:
    AIRM UI login:
      Username: $airm_user
      Password: $airm_password

    Keycloak admin console:
      Username: $keycloak_user
      Password: $keycloak_password

  IMPORTANT:
    - The TLS certificate is self-signed; browsers will show a warning.
    - Credentials are read from existing Kubernetes Secrets.
================================================================
EOF
