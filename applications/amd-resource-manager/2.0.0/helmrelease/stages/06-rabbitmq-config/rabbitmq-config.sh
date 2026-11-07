#!/bin/sh
#
# Stage 06 — Initial RabbitMQ application identity and topology
#
# This script configures RabbitMQ for AIRM. The RabbitMQ
# Cluster Operator creates the broker and admin bootstrap identity, but AIRM
# also needs:
# - publisher vhost `vh_airm_common`;
# - temporary application user `airm-user`;
# - consumer vhost `vh_airm-user`;
# - permissions for `airm-user` and the admin identity;
# - durable consumer queue `airm-user`.
#
# This is intentionally a temporary/local identity. Stage 09 registers the
# cluster and replaces the Kubernetes Secret with the returned cluster ID and
# one-time secret; stage 10 then creates the matching RabbitMQ identity,
# per-cluster vhost, and queue. The initial topology here lets management
# components start from a known baseline.
#
# Notes:
# - RabbitMQ configuration runs as its own Flux stage after the infrastructure
#   health checks.
# - Pod readiness is polled for up to 300 seconds and is a hard failure.
# - Existing users and vhosts are queried before add or change operations, so
#   retries are deterministic.
# - RabbitMQ commands are not followed by `|| true`; any failed password, vhost,
#   permission, or queue operation stops the stage.
# - The final user, vhosts, and durable queue are read back and verified.
# - The RabbitMQ pod and namespace are supplied by the Job environment.
#
# The queue declaration and permission updates are safe to repeat. Credentials
# are read from stage 01 Secrets and are never printed.
set -eu

log() {
  printf '[airm-rabbitmq-config] %s\n' "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

rmq_exec() {
  kubectl exec -n "$AIRM_NAMESPACE" "$RABBITMQ_POD" -- "$@"
}

log "Waiting for RabbitMQ pod '$RABBITMQ_POD'"
RABBITMQ_READY=false
for attempt in $(seq 1 60); do
  READY_STATUS="$(kubectl get "pod/$RABBITMQ_POD" \
    -n "$AIRM_NAMESPACE" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
    2>/dev/null || true)"
  if [ "$READY_STATUS" = "True" ]; then
    RABBITMQ_READY=true
    break
  fi
  log "RabbitMQ pod is not ready yet ($attempt/60)"
  sleep 5
done
[ "$RABBITMQ_READY" = "true" ] ||
  fail "RabbitMQ pod '$RABBITMQ_POD' was not ready after 300s"

RMQ_USER_PASS="$(kubectl get secret airm-rabbitmq-common-vhost-user \
  -n "$AIRM_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)"
RMQ_ADMIN_PASS="$(kubectl get secret airm-rabbitmq-admin \
  -n "$AIRM_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)"
[ -n "$RMQ_USER_PASS" ] || fail "airm-user password is empty"
[ -n "$RMQ_ADMIN_PASS" ] || fail "admin password is empty"

log "Synchronizing RabbitMQ users"
rmq_exec rabbitmqctl change_password admin "$RMQ_ADMIN_PASS"
if rmq_exec rabbitmqctl list_users --no-table-headers |
  awk '{print $1}' | grep -Fxq airm-user; then
  rmq_exec rabbitmqctl change_password airm-user "$RMQ_USER_PASS"
else
  rmq_exec rabbitmqctl add_user airm-user "$RMQ_USER_PASS"
fi

for vhost in vh_airm_common vh_airm-user; do
  if ! rmq_exec rabbitmqctl list_vhosts --no-table-headers |
    grep -Fxq "$vhost"; then
    rmq_exec rabbitmqctl add_vhost "$vhost"
  fi
done

log "Applying RabbitMQ permissions"
rmq_exec rabbitmqctl set_permissions -p vh_airm_common \
  airm-user ".*" ".*" ".*"
rmq_exec rabbitmqctl set_permissions -p vh_airm_common \
  admin ".*" ".*" ".*"
rmq_exec rabbitmqctl set_permissions -p / \
  airm-user ".*" ".*" ".*"
rmq_exec rabbitmqctl set_permissions -p vh_airm-user \
  airm-user ".*" ".*" ".*"
rmq_exec rabbitmqctl set_permissions -p vh_airm-user \
  admin ".*" ".*" ".*"

log "Declaring durable consumer queue 'airm-user'"
rmq_exec rabbitmqadmin -u admin -p "$RMQ_ADMIN_PASS" \
  declare queue --name=airm-user --durable=true --vhost=vh_airm-user

rmq_exec rabbitmqctl list_users --no-table-headers |
  awk '{print $1}' | grep -Fxq airm-user ||
  fail "RabbitMQ user 'airm-user' was not created"
for vhost in vh_airm_common vh_airm-user; do
  rmq_exec rabbitmqctl list_vhosts --no-table-headers |
    grep -Fxq "$vhost" ||
    fail "RabbitMQ vhost '$vhost' was not created"
done
rmq_exec rabbitmqctl list_queues -p vh_airm-user \
  name durable --no-table-headers |
  awk '$1 == "airm-user" && $2 == "true" { found = 1 } END { exit !found }' ||
  fail "durable queue 'airm-user' was not created"

log "RabbitMQ users, vhosts, permissions, and queue are configured"
