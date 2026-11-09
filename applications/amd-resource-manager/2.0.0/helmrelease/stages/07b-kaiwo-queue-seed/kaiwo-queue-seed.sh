#!/bin/sh
#
# Stage 07b — KaiwoQueueConfig seed
#
# Stage 07a applies the Kaiwo and AIM Engine CRDs and reports Ready only once
# they are Established. This stage depends on 07a, so the CRDs exist before this
# script runs, and the script does not check them again. It:
#   1. creates the cluster-scoped KaiwoQueueConfig/kaiwo seed only when it is
#      absent. An existing seed is never modified, so AIRM-managed quota state
#      is preserved across re-runs and upgrades.
#   2. re-reads the seed before reporting success, so a create that did not
#      take effect fails the stage instead of passing silently.
#
# Transient API errors while reading or creating the seed are retried a bounded
# number of times. Authorization failures fail the stage immediately so missing
# prerequisites are never masked. If the KaiwoQueueConfig API is not served, the
# read fails as a transient error and the retries end with a clear failure.
#
# No Kaiwo or AIM Engine operator workloads are installed by this script.
set -eu

readonly SEED_NAME="kaiwo"
readonly SEED_RESOURCE="kaiwoqueueconfig.kaiwo.silogen.ai"
readonly SEED_MANIFEST="/tmp/kaiwoqueueconfig-seed.yaml"
readonly MAX_ATTEMPTS=5
readonly RETRY_DELAY_SECONDS=5

log() {
  printf '[airm-kaiwo-queue-seed] %s\n' "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

# Prints "present" or "absent" and returns 0 when the state is known.
# Returns 2 for authorization failures and 1 for transient or unknown errors.
seed_state() {
  if output="$(kubectl get "$SEED_RESOURCE" "$SEED_NAME" -o name 2>&1)"; then
    printf 'present\n'
    return 0
  fi
  case "$output" in
  *NotFound*)
    printf 'absent\n'
    return 0
    ;;
  *Forbidden* | *Unauthorized*)
    log "$output"
    return 2
    ;;
  *)
    log "$output"
    return 1
    ;;
  esac
}

ensure_seed() {
  attempt=1
  while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    state_rc=0
    state="$(seed_state)" || state_rc=$?

    if [ "$state_rc" -eq 2 ]; then
      fail "not authorized to read KaiwoQueueConfig '$SEED_NAME'; check the airm-kaiwo-queue-seed RBAC"
    fi
    if [ "$state_rc" -ne 0 ]; then
      log "transient error reading KaiwoQueueConfig '$SEED_NAME' (attempt $attempt/$MAX_ATTEMPTS)"
      attempt=$((attempt + 1))
      sleep "$RETRY_DELAY_SECONDS"
      continue
    fi

    if [ "$state" = "present" ]; then
      log "KaiwoQueueConfig '$SEED_NAME' already exists; leaving it unchanged"
      return 0
    fi

    create_rc=0
    output="$(kubectl create -f "$SEED_MANIFEST" 2>&1)" || create_rc=$?
    if [ "$create_rc" -eq 0 ]; then
      log "created KaiwoQueueConfig '$SEED_NAME'"
      return 0
    fi
    case "$output" in
    *AlreadyExists*)
      # A previous attempt succeeded but its response was lost, or another
      # run created it first. Either way the object exists; leave it alone.
      log "KaiwoQueueConfig '$SEED_NAME' already exists; leaving it unchanged"
      return 0
      ;;
    *Forbidden* | *Unauthorized*)
      log "$output"
      fail "not authorized to create KaiwoQueueConfig '$SEED_NAME'; check the airm-kaiwo-queue-seed RBAC"
      ;;
    esac
    log "$output"
    log "transient error creating KaiwoQueueConfig '$SEED_NAME' (attempt $attempt/$MAX_ATTEMPTS)"
    attempt=$((attempt + 1))
    sleep "$RETRY_DELAY_SECONDS"
  done
  fail "could not ensure KaiwoQueueConfig '$SEED_NAME' after $MAX_ATTEMPTS attempts"
}

cat >"$SEED_MANIFEST" <<'EOF'
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

confirm_seed() {
  if ! output="$(kubectl get "$SEED_RESOURCE" "$SEED_NAME" -o name 2>&1)"; then
    log "$output"
    fail "KaiwoQueueConfig '$SEED_NAME' could not be read after ensuring it; the Job will retry"
  fi
  log "KaiwoQueueConfig '$SEED_NAME' is present"
}

ensure_seed
confirm_seed
