# Stage 00 — cluster preflight and runtime-value discovery
#
# This script runs inside discovery-job.yaml and performs three tasks:
#
# 1. Validate prerequisites:
#    - Confirm kubectl/jq and Kubernetes API connectivity.
#    - Require cert-manager and Gateway API CRDs.
#    - Detect CloudNativePG and the configured GatewayClass; these are warnings
#      because a later stage can install CNPG and Gateway reconciliation gives
#      the authoritative result for the GatewayClass.
#
# 2. Resolve cluster-specific configuration:
#    - Domain: explicit override, then first MetalLB pool address as nip.io,
#      then the Traefik LoadBalancer address.
#    - StorageClass: explicit override, literal `default`, annotated default,
#      then the first available class.
#    - Prometheus: explicit override, NKP kube-prometheus-stack Service, another
#      labeled Prometheus Service, then the installer-compatible LGTM fallback.
#
# 3. Publish the result:
#    Create or update `airm-discovered` in the catalog release namespace with
#    the resolved values and status `ready`. Flux injects these values into all
#    subsequent stages through `postBuild.substituteFrom`.
#
# The script exits non-zero when a required prerequisite, domain, or
# StorageClass cannot be resolved so later stages never deploy with incomplete
# configuration. It is written to be safe when the Job is retried.

log() {
  printf '%s\n' "==> $*"
}

fail() {
  printf '%s\n' "ERROR: $*" >&2
  exit 1
}

command -v kubectl >/dev/null || fail "kubectl is unavailable"
command -v jq >/dev/null || fail "jq is unavailable"
kubectl version >/dev/null || fail "cannot connect to the Kubernetes API"

log "Validating required platform dependencies"
kubectl get deployment -n cert-manager cert-manager >/dev/null \
  || fail "cert-manager deployment is not available"
if kubectl get deployments -A -l app.kubernetes.io/name=cloudnative-pg \
  -o name | grep -q .; then
  log "CloudNativePG operator found"
else
  log "WARNING: CloudNativePG operator not detected; infrastructure stage must install or provide it"
fi
kubectl get customresourcedefinition gatewayclasses.gateway.networking.k8s.io \
  >/dev/null || fail "Gateway API CRDs are not available"
kubectl get gatewayclass "$GATEWAY_CLASS_NAME" >/dev/null \
  || log "WARNING: GatewayClass $GATEWAY_CLASS_NAME is not available; gateway stage may fail"

domain="$DOMAIN_OVERRIDE"
if [ -z "$domain" ]; then
  address="$(kubectl get ipaddresspools.metallb.io -A -o json 2>/dev/null \
    | jq -r '.items[0].spec.addresses[0] // empty')"
  if [ -n "$address" ]; then
    domain="$(printf '%s' "$address" | cut -d/ -f1 | cut -d- -f1).nip.io"
  fi
fi
if [ -z "$domain" ]; then
  address="$(kubectl get services -A -l app.kubernetes.io/name=traefik \
    -o json 2>/dev/null \
    | jq -r '[.items[].status.loadBalancer.ingress[]? |
      (.ip // .hostname // empty)][0] // empty')"
  if [ -n "$address" ]; then
    case "$address" in
      *[!0-9.]*)
        domain="$address"
        ;;
      *)
        domain="$address.nip.io"
        ;;
    esac
  fi
fi
[ -n "$domain" ] || fail \
  "domain discovery failed; set discovery.domain in the application configuration"

storage_class="$STORAGE_CLASS_OVERRIDE"
if [ -z "$storage_class" ]; then
  if kubectl get storageclass default >/dev/null 2>&1; then
    storage_class=default
  else
    storage_class="$(kubectl get storageclasses -o json \
      | jq -r '[.items[] | select(
        .metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true"
        or .metadata.annotations["storageclass.beta.kubernetes.io/is-default-class"] == "true"
      ) | .metadata.name][0] // empty')"
  fi
fi
if [ -z "$storage_class" ]; then
  storage_class="$(kubectl get storageclasses -o json \
    | jq -r '.items[0].metadata.name // empty')"
fi
[ -n "$storage_class" ] || fail "no StorageClass is available"

prometheus_url="$PROMETHEUS_URL_OVERRIDE"
if [ -z "$prometheus_url" ]; then
  service="$(kubectl get service -n kommander \
    kube-prometheus-stack-prometheus -o json 2>/dev/null \
    | jq -r '.metadata.name // empty')"
  if [ -n "$service" ]; then
    prometheus_url="http://$service.kommander.svc.cluster.local:9090"
  fi
fi
if [ -z "$prometheus_url" ]; then
  service_data="$(kubectl get services -A \
    -l app.kubernetes.io/name=prometheus -o json 2>/dev/null \
    | jq -r '.items[0] |
      if . then "\(.metadata.name) \(.metadata.namespace)" else "" end')"
  if [ -n "$service_data" ]; then
    service="$(printf '%s' "$service_data" | cut -d' ' -f1)"
    namespace="$(printf '%s' "$service_data" | cut -d' ' -f2)"
    prometheus_url="http://$service.$namespace.svc.cluster.local:9090"
  fi
fi
if [ -z "$prometheus_url" ]; then
  prometheus_url="http://lgtm-stack.otel-lgtm-stack.svc.cluster.local:9090"
  log "Prometheus discovery failed; using script-compatible fallback: $prometheus_url"
fi

log "Writing discovered cluster configuration"
kubectl create configmap airm-discovered \
  --namespace "$RELEASE_NAMESPACE" \
  --from-literal=airmDomain="$domain" \
  --from-literal=airmStorageClass="$storage_class" \
  --from-literal=airmPrometheusUrl="$prometheus_url" \
  --from-literal=airmDiscoveryStatus=ready \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl get configmap airm-discovered \
  --namespace "$RELEASE_NAMESPACE" -o yaml
log "AIRM preflight discovery completed"
