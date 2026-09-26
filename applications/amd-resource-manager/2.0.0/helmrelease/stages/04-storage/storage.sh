#!/bin/sh
#
# Stage 04 — AIRM StorageClass compatibility
#
# This script is the GitOps equivalent of installer step 9b. The upstream AIRM
# PostgreSQL and RabbitMQ infrastructure charts expect a StorageClass literally
# named `default`, while NKP commonly provides another class such as
# `nutanix-volume`. If `default` is absent, this stage clones the discovered
# class definition under the name `default`.
#
# The cloned class retains the original provisioner and storage parameters but
# removes Kubernetes server metadata and default-class annotations. It is an
# alias by name for charts that explicitly request `default`; it does not
# replace or mark itself as the cluster's annotated default StorageClass.
#
# Differences from the original installer step 9b:
# 1. STORAGE_CLASS comes from stage 00 through Flux substitution instead of the
#    installer's in-process SC_NAME variable.
# 2. Storage preparation is a dedicated stage and health gate before operator
#    and infrastructure HelmReleases, rather than a substep inside step 9.
# 3. Missing, empty, or inconsistent discovery data is fatal. The installer
#    emitted a warning and could continue until PVC provisioning failed later.
# 4. The resulting `default` class is explicitly verified after apply.
#
# The operation is idempotent: if `default` already exists, the stage preserves
# it and exits without modifying cluster storage configuration.
set -eu

log() {
  printf '[airm-storage] %s\n' "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

if kubectl get storageclass default >/dev/null 2>&1; then
  log "'default' StorageClass already exists"
  exit 0
fi

[ -n "$STORAGE_CLASS" ] || fail "discovered StorageClass is empty"
[ "$STORAGE_CLASS" != "default" ] || fail \
  "StorageClass 'default' was discovered but does not exist"
kubectl get storageclass "$STORAGE_CLASS" >/dev/null 2>&1 || fail \
  "StorageClass '$STORAGE_CLASS' does not exist"

log "Creating 'default' StorageClass as alias to '$STORAGE_CLASS'"
kubectl get storageclass "$STORAGE_CLASS" -o json \
  | jq '.metadata.name = "default" |
        del(.metadata.annotations["storageclass.kubernetes.io/is-default-class"]) |
        del(.metadata.creationTimestamp, .metadata.resourceVersion,
            .metadata.uid, .metadata.managedFields)' \
  | kubectl apply -f -

kubectl get storageclass default >/dev/null 2>&1 || fail \
  "'default' StorageClass was not created"
log "'default' StorageClass is ready"
