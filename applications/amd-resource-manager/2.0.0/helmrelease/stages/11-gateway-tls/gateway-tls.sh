#!/bin/sh
#
# Stage 11 — Gateway TLS publication and external route verification
#
# This script publishes the Gateway TLS Secret and verifies the routes. The Job's
# init container generates a one-year self-signed wildcard certificate; this
# script preserves an existing TLS Secret or creates it from the generated
# files, then verifies the Gateway, all three HTTPRoutes, and their external
# HTTPS endpoints.
#
# Notes:
# - Certificate generation runs in a separate pinned openssl init container, so
#   the kubectl utility container never needs openssl installed.
# - TLS files are exchanged through a memory-backed emptyDir and are never stored
#   in a ConfigMap or Job environment variable.
# - An existing `airm-gateway-tls` is preserved. The init container still
#   generates temporary files on every run, but they are discarded when the
#   existing Secret is kept.
# - Gateway readiness requires both Programmed=True and ResolvedRefs=True for the
#   configured listener.
# - The AIRM API, AIRM UI, and Keycloak HTTPRoutes must each report Accepted=True
#   and ResolvedRefs=True.
# - The public AIRM API, UI, and Keycloak OIDC discovery endpoints are tested
#   over HTTPS. `curl -k` is intentional because this stage creates a
#   self-signed certificate; reachability and routing, not public trust, are
#   being verified.
# - Readiness and endpoint failures are hard Flux failures with bounded retries.
# - Domain, Gateway, listener, Secret, and namespace names come from catalog
#   values.
#
# The generated certificate is for development and test use. A production
# deployment should pre-create the named Secret using its approved certificate
# issuer; this stage will preserve that Secret.
set -eu

log() {
  printf '[airm-gateway-tls] %s\n' "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

gateway_ready() {
  kubectl get gateway "$GATEWAY_NAME" -n "$GATEWAY_NAMESPACE" -o json |
    jq -e --arg listener "$GATEWAY_LISTENER_NAME" '
        any(.status.listeners[]?;
          .name == $listener
          and any(.conditions[]?;
            .type == "Programmed" and .status == "True")
          and any(.conditions[]?;
            .type == "ResolvedRefs" and .status == "True")
        )
      ' >/dev/null
}

route_ready() {
  namespace=$1
  name=$2
  kubectl get httproute "$name" -n "$namespace" -o json |
    jq -e '
        any(.status.parents[]?;
          any(.conditions[]?;
            .type == "Accepted" and .status == "True")
          and any(.conditions[]?;
            .type == "ResolvedRefs" and .status == "True")
        )
      ' >/dev/null
}

wait_for() {
  description=$1
  shift
  for attempt in $(seq 1 24); do
    if "$@"; then
      log "$description is ready"
      return 0
    fi
    log "Waiting for $description ($attempt/24)"
    sleep 5
  done
  fail "$description did not become ready after 120s"
}

test_url() {
  description=$1
  url=$2
  for attempt in $(seq 1 24); do
    if curl -kfsS --connect-timeout 5 --max-time 15 \
      -o /dev/null "$url"; then
      log "$description is reachable: $url"
      return 0
    fi
    log "Waiting for $description endpoint ($attempt/24)"
    sleep 5
  done
  fail "$description endpoint is not reachable: $url"
}

[ -n "$DOMAIN" ] || fail "DOMAIN is empty"

log "Ensuring TLS secret '$TLS_SECRET' in '$GATEWAY_NAMESPACE'"
if kubectl get secret "$TLS_SECRET" -n "$GATEWAY_NAMESPACE" >/dev/null 2>&1; then
  log "TLS secret already exists; preserving it"
else
  kubectl create secret tls "$TLS_SECRET" \
    --cert=/tls/tls.crt \
    --key=/tls/tls.key \
    --namespace="$GATEWAY_NAMESPACE"
  log "TLS secret created"
fi

wait_for "Gateway listener $GATEWAY_LISTENER_NAME" gateway_ready
gateway_address="$(kubectl get gateway "$GATEWAY_NAME" \
  -n "$GATEWAY_NAMESPACE" \
  -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
if [ -n "$gateway_address" ]; then
  log "Gateway address: $gateway_address"
else
  log "Gateway has no reported address"
fi

wait_for "AIRM API HTTPRoute" route_ready "$AIRM_NAMESPACE" airmapi-route
wait_for "AIRM UI HTTPRoute" route_ready "$AIRM_NAMESPACE" airmui-route
wait_for "Keycloak HTTPRoute" \
  route_ready "$KEYCLOAK_NAMESPACE" keycloak-route

test_url "AIRM API" "https://airmapi.$DOMAIN/v1/health"
test_url "AIRM UI" "https://airmui.$DOMAIN/"
test_url "Keycloak" \
  "https://kc.$DOMAIN/realms/airm/.well-known/openid-configuration"

log "Gateway TLS, routes, and external endpoints are ready"
