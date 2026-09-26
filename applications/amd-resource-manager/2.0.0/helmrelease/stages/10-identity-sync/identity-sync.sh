#!/bin/sh
#
# Stage 10 — Registered cluster identity synchronization into RabbitMQ
#
# Stage 09 replaces the temporary Kubernetes `airm-user` credentials with the
# cluster ID and one-time secret returned by the AIRM API. This script creates
# or updates the matching RabbitMQ user, grants publisher access to
# `vh_airm_common`, creates the per-cluster consumer vhost `vh_<cluster-id>`,
# grants consumer/admin permissions, and ensures the durable cluster queue.
#
# This is the local all-mode equivalent of the RabbitMQ provisioning section in
# the installer's agent-mode `register` step. It is also the broker-side half of
# the upstream configure behavior that was removed when stage 08 set
# `includeDemoSetup: false`.
#
# Differences from the original installer provisioning logic:
# 1. Identity synchronization is a separate Flux stage after registration,
#    allowing retries without issuing another one-time cluster identity.
# 2. The Job rejects the temporary username `airm-user`; stage 09 must have
#    successfully persisted a real cluster ID before broker mutation begins.
# 3. RabbitMQ readiness is a hard 300-second gate, and kubectl exec targets the
#    named `rabbitmq` container explicitly.
# 4. User and vhost existence are checked before add/change operations rather
#    than suppressing command failures with `|| true`.
# 5. Before queue declaration, the script checks whether the API/configure flow
#    already created it. RabbitMQ rejects redeclaration if an existing queue has
#    additional immutable quorum or dead-letter arguments.
# 6. The queue declaration otherwise preserves the installer's durable-queue
#    syntax; this stage does not force different queue arguments.
# 7. User, vhost, publisher/consumer permissions, queue durability, and
#    Kubernetes/RabbitMQ identity agreement are all read back and verified.
#    The installer logged success even when provisioning commands were ignored.
# 8. No agent restart occurs here. The catalog orders agent deployment after
#    this health gate so the agent starts with synchronized credentials.
#
# This script never changes the Kubernetes identity Secret; it only reads it
# and makes RabbitMQ converge to the same identity.
set -eu

log() {
  printf '[airm-identity-sync] %s\n' "$*"
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

rmq_exec() {
  kubectl exec -n "$AIRM_NAMESPACE" "$RABBITMQ_POD" \
    -c "$RABBITMQ_CONTAINER" -- "$@"
}

log "Waiting for RabbitMQ pod '$RABBITMQ_POD'"
kubectl wait --for=condition=Ready "pod/$RABBITMQ_POD" \
  -n "$AIRM_NAMESPACE" --timeout=300s

cluster_id="$(read_secret airm-rabbitmq-common-vhost-user username)"
cluster_secret="$(read_secret airm-rabbitmq-common-vhost-user password)"
admin_password="$(read_secret airm-rabbitmq-admin password)"
[ -n "$cluster_id" ] || fail "registered cluster ID is empty"
[ "$cluster_id" != "airm-user" ] \
  || fail "temporary airm-user identity has not been replaced"
[ -n "$cluster_secret" ] || fail "registered cluster secret is empty"
[ -n "$admin_password" ] || fail "RabbitMQ admin password is empty"

log "Synchronizing RabbitMQ user '$cluster_id'"
if rmq_exec rabbitmqctl list_users --no-table-headers \
  | awk '{print $1}' | grep -Fxq "$cluster_id"; then
  rmq_exec rabbitmqctl change_password "$cluster_id" "$cluster_secret"
else
  rmq_exec rabbitmqctl add_user "$cluster_id" "$cluster_secret"
fi

rmq_exec rabbitmqctl set_permissions -p vh_airm_common \
  "$cluster_id" ".*" ".*" ".*"

consumer_vhost="vh_$cluster_id"
if ! rmq_exec rabbitmqctl list_vhosts --no-table-headers \
  | grep -Fxq "$consumer_vhost"; then
  rmq_exec rabbitmqctl add_vhost "$consumer_vhost"
fi
rmq_exec rabbitmqctl set_permissions -p "$consumer_vhost" \
  "$cluster_id" ".*" ".*" ".*"
rmq_exec rabbitmqctl set_permissions -p "$consumer_vhost" \
  admin ".*" ".*" ".*"

# Keeping the installer's declaration syntax, but not redeclaring an existing
# queue: RabbitMQ rejects redeclaration when the API-created queue has
# additional immutable quorum/DLX arguments.
if ! rmq_exec rabbitmqctl list_queues -p "$consumer_vhost" \
  name --no-table-headers | grep -Fxq "$cluster_id"; then
  log "Declaring durable queue '$cluster_id' in '$consumer_vhost'"
  rmq_exec rabbitmqadmin -u admin -p "$admin_password" \
    declare queue --name="$cluster_id" --durable=true \
    --vhost="$consumer_vhost"
fi

rmq_exec rabbitmqctl list_users --no-table-headers \
  | awk '{print $1}' | grep -Fxq "$cluster_id" \
  || fail "RabbitMQ user '$cluster_id' is missing"
rmq_exec rabbitmqctl list_vhosts --no-table-headers \
  | grep -Fxq "$consumer_vhost" \
  || fail "RabbitMQ vhost '$consumer_vhost' is missing"
rmq_exec rabbitmqctl list_permissions -p vh_airm_common \
  --no-table-headers \
  | awk -v user="$cluster_id" \
    '$1 == user && $2 == ".*" && $3 == ".*" && $4 == ".*" {
      found = 1
    } END { exit !found }' \
  || fail "publisher permissions for '$cluster_id' are missing"
for user in "$cluster_id" admin; do
  rmq_exec rabbitmqctl list_permissions -p "$consumer_vhost" \
    --no-table-headers \
    | awk -v expected="$user" \
      '$1 == expected && $2 == ".*" && $3 == ".*" && $4 == ".*" {
        found = 1
      } END { exit !found }' \
    || fail "consumer permissions for '$user' are missing"
done
rmq_exec rabbitmqctl list_queues -p "$consumer_vhost" \
  name durable --no-table-headers \
  | awk -v queue="$cluster_id" \
    '$1 == queue && $2 == "true" { found = 1 } END { exit !found }' \
  || fail "durable queue '$cluster_id' is missing"

[ "$(read_secret airm-rabbitmq-common-vhost-user username)" = "$cluster_id" ] \
  || fail "Kubernetes and RabbitMQ identities do not match"
log "RabbitMQ identity '$cluster_id' is synchronized"
