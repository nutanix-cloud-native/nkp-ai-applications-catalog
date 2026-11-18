# Stage 01 — AIRM Secret initialization
#
# This script creates the credentials expected by the CNPG, RabbitMQ, Keycloak,
# AIRM API, and AIRM UI charts before
# those components are deployed. Passwords remain hexadecimal because they are
# safe to embed in AMQP and application connection strings.
#
# Secrets created in the AIRM namespace:
# - airm-cnpg-user / airm-cnpg-superuser: PostgreSQL credentials.
# - airm-keycloak-admin-client / airm-keycloak-ui-creds: two Kubernetes views
#   of the same Keycloak client secret.
# - airm-user-credentials: initial AIRM UI user and password.
# - airm-rabbitmq-admin: operator bootstrap credentials and default_user.conf.
# - airm-rabbitmq-common-vhost-user: temporary `airm-user` identity; stage 09
#   replaces it with the cluster ID and one-time secret returned by AIRM.
# - airm-secrets-airm: UI/OIDC/API environment values.
#
# Design notes:
# - The Job reads DOMAIN from stage 00's `airm-discovered` ConfigMap, so it does
#   not depend on state left behind by another process.
# - Random hex values come from `/dev/urandom` with `od`, which the pinned
#   in-cluster utility image supports without openssl.
# - Existing Secrets are preserved, so retries are non-destructive.
# - The two Keycloak client Secrets are reconciled with apply semantics. The UI
#   Secret is preferred, then the admin-client Secret, then a new value. Stage 03
#   later makes Keycloak's value authoritative.
# - Every required Secret and key is verified after creation. A failed stage
#   stops before dependent components start.
# - The script waits for discovery status and validates in-cluster API and tool
#   access, because it runs in its own Job.

log() {
  printf '%s\n' "==> $*"
}

fail() {
  printf '%s\n' "ERROR: $*" >&2
  exit 1
}

rand_hex() {
  od -An -N "$1" -tx1 /dev/urandom | tr -d ' \n'
}

secret_exists() {
  kubectl get secret "$1" --namespace "$AIRM_NAMESPACE" >/dev/null 2>&1
}

ensure_secret() {
  name="$1"
  shift
  if secret_exists "$name"; then
    log "Secret $name already exists; preserving existing values"
    return 0
  fi
  kubectl create secret generic "$name" \
    --namespace "$AIRM_NAMESPACE" \
    "$@" \
    --dry-run=client -o yaml | kubectl apply -f -
}

apply_secret() {
  name="$1"
  shift
  kubectl create secret generic "$name" \
    --namespace "$AIRM_NAMESPACE" \
    "$@" \
    --dry-run=client -o yaml | kubectl apply -f -
}

get_secret_value() {
  kubectl get secret "$1" --namespace "$AIRM_NAMESPACE" -o json 2>/dev/null |
    jq -r --arg key "$2" '.data[$key] // empty' |
    base64 -d 2>/dev/null || true
}

require_secret_keys() {
  name="$1"
  shift
  secret_exists "$name" || fail "Secret $name is missing"
  for key in "$@"; do
    value="$(get_secret_value "$name" "$key")"
    [ -n "$value" ] || fail "Secret $name is missing required key $key"
  done
}

command -v kubectl >/dev/null || fail "kubectl is unavailable"
command -v jq >/dev/null || fail "jq is unavailable"
command -v od >/dev/null || fail "od is unavailable"
command -v tr >/dev/null || fail "tr is unavailable"
[ -r /dev/urandom ] || fail "/dev/urandom is unavailable"

AIRM_NAMESPACE="$${AIRM_NAMESPACE:?AIRM_NAMESPACE is required}"
RELEASE_NAMESPACE="$${RELEASE_NAMESPACE:?RELEASE_NAMESPACE is required}"
KEYCLOAK_CLIENT_ID="$${KEYCLOAK_CLIENT_ID:?KEYCLOAK_CLIENT_ID is required}"
AIRM_USERNAME="$${AIRM_USERNAME:?AIRM_USERNAME is required}"
# The client ID is the cluster UUID (or a legacy UUID). An unresolved Flux
# variable such as a literal clusterUUID placeholder must fail here, before
# any Keycloak client is created under that name.
printf '%s' "$KEYCLOAK_CLIENT_ID" |
  grep -Eq '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' ||
  fail "KEYCLOAK_CLIENT_ID is not a UUID: $KEYCLOAK_CLIENT_ID"

# The username becomes the local part of the login email. Keycloak stores
# usernames in lowercase, so only lowercase letters, digits, dots, dashes, and
# underscores are accepted. This also keeps the value safe in JSON bodies.
printf '%s' "$AIRM_USERNAME" |
  grep -Eq '^[a-z0-9][a-z0-9._-]{0,63}$' ||
  fail "AIRM_USERNAME must be 1-64 lowercase letters, digits, dots, dashes, or underscores: $AIRM_USERNAME"

# NOTE: Do not pass kubectl client flags such as --request-timeout here.
# With alpine/k8s kubectl v1.35, those flags disable in-cluster config and
# force http://localhost:8080 (kubernetes/kubernetes#93474). Discovery works
# because it calls kubectl without those flags.
log "Waiting for preflight discovery"
kubectl version >/dev/null ||
  fail "cannot connect to the Kubernetes API"

for attempt in $(seq 1 120); do
  err_file="$(mktemp)"
  DOMAIN="$(kubectl get configmap airm-discovered \
    --namespace "$RELEASE_NAMESPACE" \
    -o jsonpath='{.data.airmDomain}' 2>"$err_file" || true)"
  STATUS="$(kubectl get configmap airm-discovered \
    --namespace "$RELEASE_NAMESPACE" \
    -o jsonpath='{.data.airmDiscoveryStatus}' 2>>"$err_file" || true)"
  if [ -n "$DOMAIN" ] && [ "$STATUS" = "ready" ]; then
    rm -f "$err_file"
    log "Preflight discovery is ready: domain=$DOMAIN"
    break
  fi
  if [ "$attempt" -eq 1 ] || [ $((attempt % 12)) -eq 0 ]; then
    err="$(tr '\n' ' ' <"$err_file" | sed 's/[[:space:]]*$//')"
    log "Preflight discovery not ready (attempt $attempt/120, namespace=$RELEASE_NAMESPACE, domain=$${DOMAIN:-<empty>}, status=$${STATUS:-<empty>}, kubectl=$${err:-<none>})"
  fi
  rm -f "$err_file"
  sleep 5
done
[ -n "$DOMAIN" ] || fail "airm-discovered ConfigMap did not provide airmDomain in namespace $RELEASE_NAMESPACE"
[ "$STATUS" = "ready" ] || fail "airm-discovered ConfigMap status is '$${STATUS:-<empty>}', expected 'ready'"

log "Creating AIRM secrets"
UI_CLIENT_SECRET="$(get_secret_value airm-keycloak-ui-creds KEYCLOAK_SECRET)"
ADMIN_CLIENT_SECRET="$(get_secret_value airm-keycloak-admin-client client-secret)"

# The UI secret is the canonical Kubernetes source during secret initialization
# and is read first; the admin-client secret is only a fallback. If both exist
# and disagree, keep the stage moving by
# syncing the admin-client Secret to the UI value; the Keycloak configuration
# stage later reconciles both Kubernetes Secrets from Keycloak itself.
if [ -n "$UI_CLIENT_SECRET" ] && [ -n "$ADMIN_CLIENT_SECRET" ] &&
  [ "$UI_CLIENT_SECRET" != "$ADMIN_CLIENT_SECRET" ]; then
  log "Keycloak client Kubernetes Secrets differ; using airm-keycloak-ui-creds as the temporary canonical value"
fi

KC_CLIENT_SECRET="$UI_CLIENT_SECRET"
if [ -z "$KC_CLIENT_SECRET" ]; then
  KC_CLIENT_SECRET="$ADMIN_CLIENT_SECRET"
fi
if [ -z "$KC_CLIENT_SECRET" ]; then
  KC_CLIENT_SECRET="$(rand_hex 24)"
fi

ensure_secret airm-cnpg-user \
  --from-literal=username=airm_user \
  --from-literal=password="$(rand_hex 16)"

ensure_secret airm-cnpg-superuser \
  --from-literal=username=postgres \
  --from-literal=password="$(rand_hex 16)"

apply_secret airm-keycloak-admin-client \
  --from-literal=client-id="$KEYCLOAK_CLIENT_ID" \
  --from-literal=client-secret="$KC_CLIENT_SECRET"

apply_secret airm-keycloak-ui-creds \
  --from-literal=KEYCLOAK_SECRET="$KC_CLIENT_SECRET"

# The username is the local part of the login email. An existing Secret keeps its
# current value. To change the username on an installed cluster, delete
# airm-user-credentials and reconcile; the previous Keycloak user is not removed.
ensure_secret airm-user-credentials \
  --from-literal=USER_PASSWORD="$(rand_hex 8)" \
  --from-literal=USER_EMAIL="$AIRM_USERNAME@$DOMAIN"

RABBITMQ_ADMIN_PASSWORD="$(rand_hex 16)"
ensure_secret airm-rabbitmq-admin \
  --from-literal=username=admin \
  --from-literal=password="$RABBITMQ_ADMIN_PASSWORD" \
  --from-literal="default_user.conf=default_user = admin
default_pass = $RABBITMQ_ADMIN_PASSWORD"

ensure_secret airm-rabbitmq-common-vhost-user \
  --from-literal=username=airm-user \
  --from-literal=password="$(rand_hex 16)"

ensure_secret airm-secrets-airm \
  --from-literal=NEXTAUTH_SECRET="$(rand_hex 32)" \
  --from-literal=KEYCLOAK_URL="https://kc.$DOMAIN" \
  --from-literal=KEYCLOAK_REALM=airm \
  --from-literal=KEYCLOAK_CLIENT_ID="$KEYCLOAK_CLIENT_ID" \
  --from-literal=API_URL="https://airmapi.$DOMAIN"

require_secret_keys airm-cnpg-user username password
require_secret_keys airm-cnpg-superuser username password
require_secret_keys airm-keycloak-admin-client client-id client-secret
require_secret_keys airm-keycloak-ui-creds KEYCLOAK_SECRET
require_secret_keys airm-user-credentials USER_PASSWORD USER_EMAIL
require_secret_keys airm-rabbitmq-admin username password default_user.conf
require_secret_keys airm-rabbitmq-common-vhost-user username password
require_secret_keys airm-secrets-airm \
  NEXTAUTH_SECRET \
  KEYCLOAK_URL \
  KEYCLOAK_REALM \
  KEYCLOAK_CLIENT_ID \
  API_URL

log "AIRM secret initialization completed"
