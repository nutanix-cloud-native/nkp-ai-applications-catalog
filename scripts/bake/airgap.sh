# shellcheck shell=bash
# Verify and pin the images NKP's airgap scanner would otherwise miss.
#
# The scanner only sees images in real `image:` fields. Anything referenced from
# an env var, container arg, or ConfigMap value is invisible to it and so never
# gets mirrored into the airgap bundle. To make those refs visible we:
#   1. require the app to list them under airgapImages in bake-apps.yaml (a
#      lockfile) and fail the build if that list drifts from what we scan; then
#   2. emit an inert replicas:0 Deployment whose containers reference exactly
#      those images, so the scanner mirrors them without ever running a pod.
# shellcheck disable=SC2154,SC2034

pin_hidden_images_for_airgap() {
  # "hidden" = referenced somewhere (ALL_IMAGES) but not in a workload `image:`
  # field (WORKLOAD_IMAGES). `comm -23` keeps only lines unique to the first list.
  local scanned declared
  scanned="$(comm -23 <(printf '%s\n' "$ALL_IMAGES") <(printf '%s\n' "$WORKLOAD_IMAGES") |
    sed '/^$/d' | sort -u)"
  declared="$(yq -r "$VERSION_SELECTOR | .airgapImages // [] | .[]" "$CONFIG" 2>/dev/null |
    sed '/^$/d' | sort -u)"

  if [[ $declared != "$scanned" ]]; then
    fail_due_to_lockfile_mismatch "$scanned"
  fi

  # Nothing hidden: no pin needed.
  [[ -n $scanned ]] || return 0

  # Namespace comes from bake-apps.yaml (pinNamespace). The pin is inert, so this
  # only needs to be a valid namespace the airgap bundle can mirror against.
  local pin_namespace="${PIN_NAMESPACE:-default}"

  echo "==> Pinning $(count_lines "$scanned") declared airgap image(s) (ns=$pin_namespace):"
  printf '%s\n' "$scanned" | sed 's/^/      /'

  append_image_pin_deployment "$pin_namespace" "$scanned" >>"$RAW_MANIFEST"

  # The pinned refs are now real `image:` fields, so fold them into the rewrite
  # set to keep the optional rehost-registry path consistent.
  WORKLOAD_IMAGES="$ALL_IMAGES"
}

# Prints the copy-paste-ready airgapImages block and aborts the build.
fail_due_to_lockfile_mismatch() {
  local scanned="$1"
  {
    echo "ERROR: airgap image lockfile mismatch for $APP $VERSION."
    echo "  Images referenced only OUTSIDE workload 'image:' fields must be declared"
    echo "  verbatim under this version's airgapImages in $CONFIG so the airgap bundle"
    echo "  mirrors them. The current render scans:"
    echo
    echo "    airgapImages:"
    if [[ -n $scanned ]]; then
      printf '%s\n' "$scanned" | sed 's/^/      - /'
    else
      echo "      [] # none scanned; remove the airgapImages key"
    fi
    echo
    echo "  Update $CONFIG to match exactly, then re-run."
  } >&2
  exit 1
}

# Emits an inert Deployment (replicas: 0, so it never schedules a pod) whose
# containers list the hidden images, purely so the airgap scanner discovers and
# mirrors them. Args: $1 = namespace, $2 = newline-separated image list.
append_image_pin_deployment() {
  local namespace="$1" images="$2"
  printf '\n---\n'
  printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n'
  printf '  name: %s-airgap-image-pin\n' "$APP"
  printf '  namespace: %s\n' "$namespace"
  printf '  annotations:\n'
  printf '    nkp.nutanix.com/description: "Inert image pin (replicas: 0, never scheduled); ensures the airgapped catalog bundle mirrors images referenced only in env/args/ConfigMap values."\n'
  printf 'spec:\n  replicas: 0\n'
  printf '  selector:\n    matchLabels:\n      app: %s-airgap-image-pin\n' "$APP"
  printf '  template:\n    metadata:\n      labels:\n        app: %s-airgap-image-pin\n' "$APP"
  printf '    spec:\n      containers:\n'
  local i=0
  while IFS= read -r image; do
    [[ -z $image ]] && continue
    printf '      - name: image-pin-%s\n        image: %s\n' "$i" "$image"
    i=$((i + 1))
  done <<<"$images"
}

# Counts non-empty lines in a newline-separated string.
count_lines() {
  printf '%s\n' "$1" | grep -c .
}
