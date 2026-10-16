#!/bin/sh
#
# Stage 05 — RabbitMQ operator assurance
#
# CloudNativePG is a required NKP application dependency and stage 00 has
# already verified that exactly one operator is Ready. This stage only assures
# the AIRM-owned RabbitMQ Cluster Operator before stage 05-infrastructure
# creates its RabbitmqCluster custom resource.
#
# Differences from the original installer:
#
# RabbitMQ Cluster Operator (script step 4):
# 1. The installer downloaded `releases/latest`, whose content can change. This
#    stage uses an explicit version and verifies its manifest digest.
# 2. The installer tolerated rollout failure with `|| true`; this stage fails
#    if the operator does not become ready because infrastructure reconciliation
#    cannot succeed without it.
#
# Behavior changes:
# 3. Manifest installation uses server-side apply for large CRDs and repeatable
#    reconciliation. Existing operators are not upgraded or taken over.
# 4. Readiness is a hard stage gate with a five-minute rollout timeout. Flux
#    may retry the idempotent Job after transient failures.

set -eu

log() {
  printf '[airm-operators] %s\n' "$*"
}

apply_verified() {
  url=$1
  digest=$2
  file=$3

  curl -fsSL "$url" -o "$file"
  printf '%s  %s\n' "$${digest#sha256:}" "$file" | sha256sum -c -
  kubectl apply --server-side -f "$file"
}

if kubectl get deployment rabbitmq-cluster-operator \
  -n rabbitmq-system >/dev/null 2>&1; then
  log "RabbitMQ Cluster Operator found; skipping fallback"
else
  log "Installing RabbitMQ Cluster Operator $RABBITMQ_VERSION"
  apply_verified \
    "https://github.com/rabbitmq/cluster-operator/releases/download/$RABBITMQ_VERSION/cluster-operator.yml" \
    "$RABBITMQ_MANIFEST_DIGEST" /tmp/rabbitmq.yaml
fi
kubectl rollout status deployment/rabbitmq-cluster-operator \
  -n rabbitmq-system --timeout=300s

log "RabbitMQ Cluster Operator is ready"
