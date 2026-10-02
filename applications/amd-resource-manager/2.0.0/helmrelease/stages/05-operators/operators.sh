#!/bin/sh
#
# Stage 05 — CloudNativePG and RabbitMQ operator assurance
#
# This script combines installer steps 3 and 4. It first reuses operators
# already supplied by NKP; when an operator is absent, it installs the pinned
# upstream release manifest. Both operators must be ready before stage
# 05-infrastructure creates their Cluster and RabbitmqCluster custom resources.
#
# Differences from the original installer:
#
# CloudNativePG (script step 3):
# 1. The installer added the CNPG Helm repository and installed its chart. This
#    stage applies CNPG's official release manifest because an in-cluster Job
#    does not run host-side Helm or maintain a Helm repository.
# 2. The manifest version and SHA-256 digest are supplied by catalog values.
#    The downloaded file is verified before any cluster mutation.
# 3. Existing CNPG is discovered by its standard deployment label across all
#    namespaces, preserving an NKP-provided installation.
#
# RabbitMQ Cluster Operator (script step 4):
# 4. The installer downloaded `releases/latest`, whose content can change. This
#    stage uses an explicit version and verifies its manifest digest.
# 5. The installer tolerated rollout failure with `|| true`; this stage fails
#    if the operator does not become ready because infrastructure reconciliation
#    cannot succeed without it.
#
# Shared behavior changes:
# 6. Manifest installation uses server-side apply for large CRDs and repeatable
#    reconciliation. Existing operators are not upgraded or taken over.
# 7. Readiness is a hard stage gate with a five-minute rollout timeout for each
#    deployment. Flux may retry the idempotent Job after transient failures.

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

cnpg_location=$(kubectl get deployments -A \
  -l app.kubernetes.io/name=cloudnative-pg \
  -o jsonpath='{.items[0].metadata.namespace}{" "}{.items[0].metadata.name}' \
  2>/dev/null || true)
if [ -n "$cnpg_location" ]; then
  cnpg_namespace=$(printf '%s' "$cnpg_location" | cut -d' ' -f1)
  cnpg_deployment=$(printf '%s' "$cnpg_location" | cut -d' ' -f2)
  log "CloudNativePG operator found in '$cnpg_namespace'; skipping fallback"
else
  log "Installing CloudNativePG operator $CNPG_VERSION"
  cnpg_release="$${CNPG_VERSION#v}"
  cnpg_release="$${cnpg_release%.*}"
  apply_verified \
    "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-$${cnpg_release}/releases/cnpg-$${CNPG_VERSION#v}.yaml" \
    "$CNPG_MANIFEST_DIGEST" /tmp/cnpg.yaml
  cnpg_namespace=cnpg-system
  cnpg_deployment=cnpg-controller-manager
fi
kubectl rollout status "deployment/$cnpg_deployment" \
  -n "$cnpg_namespace" --timeout=300s

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

log "Required operators are ready"
