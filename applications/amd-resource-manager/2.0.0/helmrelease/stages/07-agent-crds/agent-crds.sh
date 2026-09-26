#!/bin/sh
#
# Stage 07 — Kaiwo and AIM Engine API prerequisites
#
# This script implements installer steps 10c and 10c2. The AIRM agent watches
# Kaiwo and AMD Inference Microservices resources, so their CRDs must be
# established before management/bootstrap and the eventual agent deployment.
# Only Kaiwo CRDs are extracted from its combined release manifest; the Kaiwo
# controller, namespace, and RBAC are intentionally not installed. AIM Engine
# provides a CRD-only release file.
#
# The stage also creates the cluster-scoped `KaiwoQueueConfig/kaiwo` seed
# expected by AIRM when it updates quota allocation state. Without this object,
# project and quota operations can fail even when the CRDs exist.
#
# Differences from the original installer steps 10c/10c2:
# 1. Both downloaded release artifacts are verified against catalog-pinned
#    SHA-256 digests before anything is applied. The installer trusted the URLs.
# 2. Versions and digests are injected by the orchestration chart rather than
#    relying only on shell defaults.
# 3. Kaiwo's manifest is downloaded to a file and verified before the same
#    CRD-only Python/YAML extraction is performed.
# 4. `kubectl wait` has a 120-second hard timeout. The installer used 30 seconds
#    and suppressed timeout failure with `|| true`.
# 5. The extracted CRD count and the final seed object are explicitly checked;
#    missing prerequisites fail the stage instead of merely logging success.
# 6. This is a dedicated Flux health gate, so retries are isolated from AIRM
#    chart installation and are safe through server-side/apply semantics.
#
# No Kaiwo or AIM Engine operator workloads are installed by this script.
set -eu

log() {
  printf '[airm-agent-crds] %s\n' "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

verify_file() {
  digest=$1
  file=$2
  expected="$(printf '%s' "$digest" | cut -d: -f2)"
  printf '%s  %s\n' "$expected" "$file" | sha256sum -c -
}

kaiwo_url="https://github.com/silogen/kaiwo/releases/download/$KAIWO_VERSION/install.yaml"
aim_url="https://github.com/amd-enterprise-ai/aim-engine/releases/download/$AIM_ENGINE_VERSION/crds.yaml"

log "Downloading Kaiwo $KAIWO_VERSION release manifest"
curl -fsSL "$kaiwo_url" -o /tmp/kaiwo-install.yaml
verify_file "$KAIWO_MANIFEST_DIGEST" /tmp/kaiwo-install.yaml

python3 - /tmp/kaiwo-install.yaml /tmp/kaiwo-crds.yaml <<'PY'
import sys
import yaml

source, destination = sys.argv[1:]
with open(source, encoding="utf-8") as stream:
    documents = [
        document
        for document in yaml.safe_load_all(stream)
        if document and document.get("kind") == "CustomResourceDefinition"
    ]
with open(destination, "w", encoding="utf-8") as stream:
    yaml.safe_dump_all(documents, stream, explicit_start=True, sort_keys=False)
print(len(documents))
PY

kaiwo_crd_count="$(grep -c 'kind: CustomResourceDefinition' \
  /tmp/kaiwo-crds.yaml || true)"
[ "$kaiwo_crd_count" -gt 0 ] \
  || fail "Kaiwo release contained no CustomResourceDefinitions"
kubectl apply --server-side -f /tmp/kaiwo-crds.yaml
log "Applied $kaiwo_crd_count Kaiwo CRDs"

log "Downloading AIM Engine $AIM_ENGINE_VERSION CRDs"
curl -fsSL "$aim_url" -o /tmp/aim-crds.yaml
verify_file "$AIM_ENGINE_CRDS_DIGEST" /tmp/aim-crds.yaml
kubectl apply --server-side -f /tmp/aim-crds.yaml

kubectl wait --for=condition=Established crd \
  kaiwoqueueconfigs.kaiwo.silogen.ai \
  kaiwojobs.kaiwo.silogen.ai \
  kaiwoservices.kaiwo.silogen.ai \
  aimservices.aim.eai.amd.com \
  --timeout=120s

log "Ensuring KaiwoQueueConfig seed object"
kubectl apply -f - <<'EOF'
apiVersion: kaiwo.silogen.ai/v1alpha1
kind: KaiwoQueueConfig
metadata:
  name: kaiwo
spec:
  resourceFlavors:
  - name: default-resource-flavor
  clusterQueues: []
  workloadPriorityClasses: []
EOF

kubectl get kaiwoqueueconfig.kaiwo.silogen.ai kaiwo >/dev/null \
  || fail "KaiwoQueueConfig 'kaiwo' was not created"
log "Kaiwo and AIM Engine CRDs are established"
