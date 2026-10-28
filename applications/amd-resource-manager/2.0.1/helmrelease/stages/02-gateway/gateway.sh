# Stage 02 — Gateway API compatibility and AIRM Gateway
#
# This script combines steps 5 and 6 from
# install-amd-resource-manager-helm-charts-copy.sh:
# - Step 5 applies Gateway API standard CRDs new enough for the NKP Traefik
#   controller (v1.4.0 by default, including BackendTLSPolicy v1 support).
# - Step 6 creates the shared Gateway used by the AIRM and Keycloak HTTPRoutes.
#
# Listener ports 8443 (`websecure`) and 8000 (`web`) are intentional. They are
# the ports of NKP Traefik's internal entrypoints, not the external Service
# ports 443 and 80. Using the Service ports causes Traefik to reject the
# Gateway with a PortUnavailable condition.
#
# Differences from the original installer steps 5 and 6:
# 1. Version, Gateway name/class/listener, TLS Secret, and workload namespaces
#    are supplied by the catalog config (helmrelease/cm.yaml) instead of being shell constants.
# 2. The Gateway is created in `${releaseNamespace}` rather than the script's
#    hardcoded `kommander` namespace, so it follows the NKP catalog instance.
# 3. `allowedRoutes` is restricted to the AIRM and Keycloak namespaces using
#    Kubernetes' built-in namespace-name label. The script used `from: All`.
# 4. The Gateway API version remains v1.4.0 by default but is configurable;
#    the script embedded the release URL directly. The upgrade is skipped when
#    the cluster already serves all APIs required by AIRM.
# 5. A failed CRD apply or compatibility check is fatal. The stage must not
#    continue against incomplete or incompatible API definitions.
# 6. This stage only references `airm-gateway-tls`; it does not create the TLS
#    Secret. The original script creates a self-signed Secret later in step 11.
#    The catalog deployment therefore requires that Secret to be supplied by
#    the intended TLS/certificate workflow.
#
# Applying both the CRDs and Gateway is idempotent, so Flux may safely retry
# this Job after transient API or network failures.

log() {
  printf '%s\n' "==> $*"
}

fail() {
  printf '%s\n' "ERROR: $*" >&2
  exit 1
}

command -v kubectl >/dev/null || fail "kubectl is unavailable"
command -v jq >/dev/null || fail "jq is unavailable"

RELEASE_NAMESPACE="$${RELEASE_NAMESPACE:?RELEASE_NAMESPACE is required}"
GATEWAY_NAME="$${GATEWAY_NAME:?GATEWAY_NAME is required}"
GATEWAY_NAMESPACE="$${GATEWAY_NAMESPACE:-$RELEASE_NAMESPACE}"
GATEWAY_CLASS_NAME="$${GATEWAY_CLASS_NAME:?GATEWAY_CLASS_NAME is required}"
GATEWAY_LISTENER_NAME="$${GATEWAY_LISTENER_NAME:?GATEWAY_LISTENER_NAME is required}"
GATEWAY_TLS_SECRET_NAME="$${GATEWAY_TLS_SECRET_NAME:?GATEWAY_TLS_SECRET_NAME is required}"
AIRM_NAMESPACE="$${AIRM_NAMESPACE:?AIRM_NAMESPACE is required}"
KEYCLOAK_NAMESPACE="$${KEYCLOAK_NAMESPACE:?KEYCLOAK_NAMESPACE is required}"
DOMAIN="$${DOMAIN:?DOMAIN is required (from airm-discovered airmDomain)}"
GATEWAY_API_VERSION="$${GATEWAY_API_VERSION:?GATEWAY_API_VERSION is required}"

gateway_api_ready() {
  for crd in \
    gatewayclasses.gateway.networking.k8s.io \
    gateways.gateway.networking.k8s.io \
    httproutes.gateway.networking.k8s.io \
    backendtlspolicies.gateway.networking.k8s.io; do
    kubectl wait --timeout=120s --for=condition=Established "crd/$crd" || return 1
  done

  kubectl get crd backendtlspolicies.gateway.networking.k8s.io -o json |
    jq -e '
      any(.spec.versions[];
        .name == "v1" and .served == true and .storage == true
      )
    ' >/dev/null
}

# Script step 5: Traefik v3.6+ needs BackendTLSPolicy at v1 (Gateway API v1.4.0+).
if gateway_api_ready; then
  log "Gateway API already provides the APIs required by AIRM; skipping CRD upgrade"
else
  log "Upgrading Gateway API to $${GATEWAY_API_VERSION} standard CRDs"
  kubectl apply -f \
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/$${GATEWAY_API_VERSION}/standard-install.yaml" ||
    fail "failed to apply Gateway API CRDs"
fi
gateway_api_ready ||
  fail "Gateway API is incompatible after upgrade; BackendTLSPolicy v1 and standard APIs are required"

# Script step 6: Traefik-backed Gateway (listener ports = Traefik entrypoints).
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
