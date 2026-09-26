#!/bin/sh
#
# Stage 09 — Local-cluster registration and identity persistence
#
# This script replaces the cluster-registration portion of the upstream AIRM
# chart's `configure.sh` Job in all mode. Stage 08 disables that Job with
# `includeDemoSetup: false`; this stage authenticates as the default AIRM user,
# registers the local NKP cluster through the AIRM API, and replaces the
# temporary `airm-user` Kubernetes Secret with the returned cluster ID and
# one-time RabbitMQ secret.
#
# Relationship to the tested installer:
# - In all mode, installer step 10 enabled the chart configure Job.
# - Installer step 2 patched configure.sh so the pre-created RabbitMQ Secret was
#   replaced with `kubectl apply` and the agent restarted.
# - The script's explicit `register` step serves remote agent-mode clusters
#   using management-cluster kubeconfig/API/RabbitMQ arguments. This stage is
#   local all-mode registration and therefore does not use cross-cluster access.
#
# Differences from the original all-mode configure flow and installer patch:
# 1. Registration is a dedicated, observable Flux Job instead of hidden inside
#    the API chart's configure Job.
# 2. Keycloak and AIRM are called through stable internal Services; no public
#    route, management kubeconfig, or pod exec is needed.
# 3. Before POSTing, the Job lists registered clusters and matches the stable
#    kubeApiUrl plus the persisted cluster ID. A complete prior registration is
#    preserved, making retries idempotent.
# 4. If the API already has this kubeApiUrl but the one-time local credential is
#    missing, the Job fails instead of registering again and leaking another
#    unrecoverable identity.
# 5. Token and registration HTTP status/body fields are validated explicitly.
# 6. The installer's patched apply semantics are preserved when replacing
#    `airm-rabbitmq-common-vhost-user`.
# 7. The agent is not restarted or installed here. Stage 10 first provisions
#    the corresponding RabbitMQ user/vhost/queue; agent deployment is ordered
#    afterward so it never starts with the temporary identity.
# 8. The local all-mode payload uses `https://aiwbui.$DOMAIN/`; the script's
#    remote-agent `register` path uses `https://workspaces.$DOMAIN/`.
#
# The AIRM API returns the RabbitMQ secret only once. Protecting and preserving
# the updated Kubernetes Secret is therefore essential for safe reconciliation.
set -eu

log() {
  printf '[airm-registration] %s\n' "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

read_secret() {
  name=$1
  key=$2
  kubectl get secret "$name" -n "$AIRM_NAMESPACE" \
    -o "jsonpath={.data.$key}" | base64 -d
}

AIRM_API_URL="http://airm-api.$AIRM_NAMESPACE.svc.cluster.local"
KEYCLOAK_URL="http://keycloak.$KEYCLOAK_NAMESPACE.svc.cluster.local:80"

USER_EMAIL="$(read_secret airm-user-credentials USER_EMAIL)"
USER_PASSWORD="$(read_secret airm-user-credentials USER_PASSWORD)"
KEYCLOAK_CLIENT_SECRET="$(read_secret airm-keycloak-ui-creds KEYCLOAK_SECRET)"
[ -n "$USER_EMAIL" ] || fail "AIRM user email is empty"
[ -n "$USER_PASSWORD" ] || fail "AIRM user password is empty"
[ -n "$KEYCLOAK_CLIENT_SECRET" ] || fail "Keycloak client secret is empty"

log "Waiting for AIRM API"
for attempt in $(seq 1 120); do
  if curl -fsS "$AIRM_API_URL/v1/health" >/dev/null 2>&1; then
    break
  fi
  [ "$attempt" -lt 120 ] || fail "AIRM API did not become ready"
  sleep 5
done

token_response_file="$(mktemp)"
token_status="$(curl -sS -o "$token_response_file" -w '%{http_code}' \
  --data-urlencode "client_id=$KEYCLOAK_CLIENT_ID" \
  --data-urlencode "username=$USER_EMAIL" \
  --data-urlencode "password=$USER_PASSWORD" \
  --data-urlencode grant_type=password \
  --data-urlencode "client_secret=$KEYCLOAK_CLIENT_SECRET" \
  "$KEYCLOAK_URL/realms/airm/protocol/openid-connect/token")"
TOKEN="$(jq -r '.access_token // empty' "$token_response_file")"
if [ "$token_status" != "200" ] || [ -z "$TOKEN" ]; then
  jq -c '{error, error_description}' "$token_response_file" >&2 || true
  rm -f "$token_response_file"
  fail "failed to obtain the AIRM user access token (HTTP $token_status)"
fi
rm -f "$token_response_file"

clusters="$(curl -fsS "$AIRM_API_URL/v1/clusters" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json")"
expected_kube_api_url="https://k8s.$DOMAIN"
existing_username="$(read_secret \
  airm-rabbitmq-common-vhost-user username)"
existing_password="$(read_secret \
  airm-rabbitmq-common-vhost-user password)"

# Registration does not submit a cluster name. Use the stable Kubernetes API
# URL and the persisted cluster ID to identify a previous registration.
cluster_id="$(printf '%s' "$clusters" | jq -r \
  --arg id "$existing_username" \
  --arg kube_api "$expected_kube_api_url" '
    .data[]?
    | select(.id == $id)
    | select((.kubeApiUrl // .kube_api_url // "") == $kube_api)
    | .id
  ' | head -n 1)"
if [ -n "$cluster_id" ] && [ -n "$existing_password" ]; then
  log "Cluster '$cluster_id' is already registered and its identity is preserved"
  exit 0
fi

# If the API contains this cluster but its one-time credentials are not
# available locally, registering again would leak another unrecoverable
# identity. Stop and require explicit operator recovery instead.
cluster_id="$(printf '%s' "$clusters" | jq -r \
  --arg kube_api "$expected_kube_api_url" '
    .data[]?
    | select((.kubeApiUrl // .kube_api_url // "") == $kube_api)
    | .id
  ' | head -n 1)"
[ -z "$cluster_id" ] \
  || fail "cluster '$cluster_id' is already registered for $expected_kube_api_url but its one-time identity is not available in airm-rabbitmq-common-vhost-user"

log "Registering the local cluster"
payload="$(jq -n \
  --arg workbench "https://aiwbui.$DOMAIN/" \
  --arg kube_api "$expected_kube_api_url" \
  '{workbenchBaseUrl: $workbench, kubeApiUrl: $kube_api}')"
response_file="$(mktemp)"
status="$(curl -sS -o "$response_file" -w '%{http_code}' \
  -X POST "$AIRM_API_URL/v1/clusters" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$payload")"
case "$status" in
  200|201)
    ;;
  *)
    cat "$response_file" >&2
    fail "cluster registration failed with HTTP $status"
    ;;
esac

cluster_id="$(jq -r '.id // empty' "$response_file")"
cluster_secret="$(jq -r '.userSecret // empty' "$response_file")"
rm -f "$response_file"
[ -n "$cluster_id" ] || fail "cluster registration returned no cluster ID"
[ -n "$cluster_secret" ] || fail "cluster registration returned no user secret"

# Preserve the installer's configure.sh patch: replace the temporary airm-user
# credentials using apply semantics. The agent is intentionally installed later.
kubectl create secret generic airm-rabbitmq-common-vhost-user \
  --from-literal="username=$cluster_id" \
  --from-literal="password=$cluster_secret" \
  -n "$AIRM_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

[ "$(read_secret airm-rabbitmq-common-vhost-user username)" = "$cluster_id" ] \
  || fail "registered cluster identity was not persisted"
log "Registered local cluster '$cluster_id' and persisted its RabbitMQ identity"
