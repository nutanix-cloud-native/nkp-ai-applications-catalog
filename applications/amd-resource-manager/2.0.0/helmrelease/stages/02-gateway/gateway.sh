# Stage 02 — AIRM Gateway
#
# This script creates the shared Gateway used by the AIRM and Keycloak HTTPRoutes.
#
# This stage does not apply Gateway API CRDs. The CRDs, including
# BackendTLSPolicy v1, are provided by the NKP gateway-api-crds platform
# application and verified by 00-preflight before this stage runs. This stage
# never installs or upgrades them.
#
# Listener ports 8443 (`websecure`) and 8000 (`web`) are intentional. They are
# the ports of NKP Traefik's internal entrypoints, not the external Service
# ports 443 and 80. Using the Service ports causes Traefik to reject the
# Gateway with a PortUnavailable condition.
#
# Notes:
# - Gateway name, class, listener, TLS Secret, and workload namespaces are
#   supplied by the orchestration chart rather than hardcoded.
# - The Gateway is created in the catalog release namespace.
# - `allowedRoutes` is restricted to the AIRM and Keycloak namespaces using the
#   built-in namespace-name label.
# - Gateway API CRDs are not applied or upgraded here. The NKP gateway-api-crds
#   platform application owns them, and 00-preflight verifies them.
# - Gateway API compatibility is enforced in 00-preflight, which stops the stage
#   chain before this stage runs against incompatible API definitions.
# - This stage only references `airm-gateway-tls`. Stage 11 creates or preserves
#   that Secret.
#
# Applying the Gateway is idempotent, so Flux may safely retry this Job after
# transient API or network failures.

log() {
  printf '%s\n' "==> $*"
}

fail() {
  printf '%s\n' "ERROR: $*" >&2
  exit 1
}

command -v kubectl >/dev/null || fail "kubectl is unavailable"

RELEASE_NAMESPACE="$${RELEASE_NAMESPACE:?RELEASE_NAMESPACE is required}"
GATEWAY_NAME="$${GATEWAY_NAME:?GATEWAY_NAME is required}"
GATEWAY_NAMESPACE="$${GATEWAY_NAMESPACE:-$RELEASE_NAMESPACE}"
GATEWAY_CLASS_NAME="$${GATEWAY_CLASS_NAME:?GATEWAY_CLASS_NAME is required}"
GATEWAY_LISTENER_NAME="$${GATEWAY_LISTENER_NAME:?GATEWAY_LISTENER_NAME is required}"
GATEWAY_TLS_SECRET_NAME="$${GATEWAY_TLS_SECRET_NAME:?GATEWAY_TLS_SECRET_NAME is required}"
AIRM_NAMESPACE="$${AIRM_NAMESPACE:?AIRM_NAMESPACE is required}"
KEYCLOAK_NAMESPACE="$${KEYCLOAK_NAMESPACE:?KEYCLOAK_NAMESPACE is required}"
DOMAIN="$${DOMAIN:?DOMAIN is required (from airm-discovered airmDomain)}"
# The Gateway API CRDs are platform-provided and
# already verified by 00-preflight, so no CRD upgrade is required here.
log "Gateway API CRD upgrade is not required; platform-provided CRDs (including BackendTLSPolicy v1) were verified by 00-preflight"

# Traefik-backed Gateway (listener ports = Traefik entrypoints).
log "Creating/updating Gateway $${GATEWAY_NAME} in $${GATEWAY_NAMESPACE}"
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: $${GATEWAY_NAME}
  namespace: $${GATEWAY_NAMESPACE}
  annotations:
    cert-manager.io/cluster-issuer: ""
spec:
  gatewayClassName: $${GATEWAY_CLASS_NAME}
  listeners:
  - name: $${GATEWAY_LISTENER_NAME}
    protocol: HTTPS
    port: 8443
    hostname: "*.$${DOMAIN}"
    tls:
      mode: Terminate
      certificateRefs:
      - name: $${GATEWAY_TLS_SECRET_NAME}
        namespace: $${GATEWAY_NAMESPACE}
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchExpressions:
          - key: kubernetes.io/metadata.name
            operator: In
            values:
            - $${AIRM_NAMESPACE}
            - $${KEYCLOAK_NAMESPACE}
  - name: web
    protocol: HTTP
    port: 8000
    hostname: "*.$${DOMAIN}"
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchExpressions:
          - key: kubernetes.io/metadata.name
            operator: In
            values:
            - $${AIRM_NAMESPACE}
            - $${KEYCLOAK_NAMESPACE}
EOF

log "Gateway $${GATEWAY_NAME} applied"
kubectl get gateway -n "$${GATEWAY_NAMESPACE}" --no-headers 2>/dev/null || true
log "AIRM gateway stage completed"
