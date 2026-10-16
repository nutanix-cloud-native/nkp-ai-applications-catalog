# Stage 00 — cluster preflight and runtime-value discovery
#
# This script runs inside discovery-job.yaml and performs three tasks:
#
# 1. Validate required NKP application dependencies:
#    - Confirm kubectl/jq and Kubernetes API connectivity.
#    - Wait for CloudNativePG, Gateway API CRDs, Prometheus, and Traefik.
#    - Fail if they do not become ready within the dependency timeout. These
#      dependencies are declared in metadata.yaml and are owned by NKP; AIRM
#      must not install replacement controllers when reconciliation is delayed.
#
# 2. Resolve cluster-specific configuration:
#    - Domain: explicit override, then first MetalLB pool address as nip.io,
#      then the Traefik LoadBalancer address.
#    - StorageClass: explicit override, literal `default`, annotated default,
#      then the first available class.
#    - Prometheus: explicit override, the NKP kube-prometheus-stack Service in
#      any namespace, then another labeled Prometheus Service.
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

prometheus_service_data() {
  result="$(kubectl get services -A -o json 2>/dev/null |
    jq -r '
      [.items[] | select(
        .metadata.name == "kube-prometheus-stack-prometheus"
      )][0] |
      if . then "\(.metadata.name) \(.metadata.namespace)" else "" end
    ')"
  if [ -n "$result" ]; then
    printf '%s\n' "$result"
    return
  fi

  kubectl get services -A -l app.kubernetes.io/name=prometheus \
    -o json 2>/dev/null |
    jq -r '.items[0] |
      if . then "\(.metadata.name) \(.metadata.namespace)" else "" end'
}

dependencies_ready() {
  cnpg="$(kubectl get deployments -A \
    -l app.kubernetes.io/name=cloudnative-pg -o json 2>/dev/null ||
    printf '{"items":[]}')"
  cnpg_count="$(printf '%s' "$cnpg" | jq '.items | length')"
  [ "$cnpg_count" -le 1 ] ||
    fail "multiple CloudNativePG operators detected; exactly one may manage AIRM"
  [ "$cnpg_count" -eq 1 ] || return 1
  printf '%s' "$cnpg" | jq -e '
    .items[0] |
    (.spec.replicas // 1) > 0 and
    (.status.availableReplicas // 0) >= (.spec.replicas // 1)
  ' >/dev/null || return 1

  kubectl get crd gatewayclasses.gateway.networking.k8s.io >/dev/null 2>&1 ||
    return 1
  kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 ||
    return 1
  kubectl get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1 ||
    return 1
  kubectl get gatewayclass "$GATEWAY_CLASS_NAME" >/dev/null 2>&1 || return 1

  kubectl get statefulsets -A -l app.kubernetes.io/name=prometheus \
    -o json 2>/dev/null |
    jq -e '
      [.items[] | select(
        (.spec.replicas // 1) > 0 and
        (.status.readyReplicas // 0) >= (.spec.replicas // 1)
      )] | length > 0
    ' >/dev/null || return 1
  [ -n "$(prometheus_service_data)" ] || return 1

  kubectl get deployments -A -l app.kubernetes.io/name=traefik \
    -o json 2>/dev/null |
    jq -e '
      [.items[] | select(
        (.spec.replicas // 1) > 0 and
        (.status.availableReplicas // 0) >= (.spec.replicas // 1)
      )] | length > 0
    ' >/dev/null || return 1
}

log "Waiting for required NKP application dependencies"
dependency_timeout_seconds=900
dependency_poll_seconds=10
dependency_deadline="$(($(date +%s) + dependency_timeout_seconds))"
until dependencies_ready; do
  if [ "$(date +%s)" -ge "$dependency_deadline" ]; then
    fail "required dependencies did not become ready within $dependency_timeout_seconds seconds: cloudnative-pg, gateway-api-crds, kube-prometheus-stack, traefik"
  fi
  sleep "$dependency_poll_seconds"
done
log "Required NKP application dependencies are ready"

domain="$DOMAIN_OVERRIDE"
if [ -z "$domain" ]; then
  address="$(kubectl get ipaddresspools.metallb.io -A -o json 2>/dev/null |
    jq -r '.items[0].spec.addresses[0] // empty')"
  if [ -n "$address" ]; then
    domain="$(printf '%s' "$address" | cut -d/ -f1 | cut -d- -f1).nip.io"
  fi
fi
if [ -z "$domain" ]; then
  address="$(kubectl get services -A -l app.kubernetes.io/name=traefik \
    -o json 2>/dev/null |
    jq -r '[.items[].status.loadBalancer.ingress[]? |
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
    storage_class="$(kubectl get storageclasses -o json |
      jq -r '[.items[] | select(
        .metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true"
        or .metadata.annotations["storageclass.beta.kubernetes.io/is-default-class"] == "true"
      ) | .metadata.name][0] // empty')"
  fi
fi
if [ -z "$storage_class" ]; then
  storage_class="$(kubectl get storageclasses -o json |
    jq -r '.items[0].metadata.name // empty')"
fi
[ -n "$storage_class" ] || fail "no StorageClass is available"

prometheus_url="$PROMETHEUS_URL_OVERRIDE"
if [ -z "$prometheus_url" ]; then
  service_data="$(prometheus_service_data)"
  if [ -n "$service_data" ]; then
    service="$(printf '%s' "$service_data" | cut -d' ' -f1)"
    namespace="$(printf '%s' "$service_data" | cut -d' ' -f2)"
    prometheus_url="http://$service.$namespace.svc.cluster.local:9090"
  fi
fi
if [ -z "$prometheus_url" ]; then
  fail "ready Prometheus was detected but no Prometheus Service endpoint could be discovered"
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
