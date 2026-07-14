# shellcheck shell=bash
# Make sure images the airgap scanner can't see still get bundled.
#
# The scanner only finds images in real `image:` fields. Images referenced from an
# env var, arg, or ConfigMap value are invisible. Apps declare those under
# airgapImages in bake-apps.yaml (checked against a fresh scan), and we surface
# them by app type:
#   - chart apps: listed in helmrelease/extra-images.txt, which the bundler reads.
#   - flat apps: pinned in an inert replicas:0 Deployment (fallback for apps not
#     yet converted to a chart).
# shellcheck disable=SC2154,SC2034

EXTRA_IMAGES_FILENAME="extra-images.txt"

# Check the airgapImages lockfile against a fresh scan and save the hidden image
# list in HIDDEN_IMAGES. Flat apps get the inert pin here (it must be in the
# manifest before packaging); chart apps use write_extra_images_file after save.
collect_hidden_images_for_airgap() {
  # "hidden" = referenced somewhere (ALL_IMAGES) but not in a workload `image:`
  # field (WORKLOAD_IMAGES). `comm -23` keeps only the lines unique to the first
  # (sorted) list, i.e. the leftovers that aren't real image fields.
  # Example: ALL_IMAGES={busybox, gcr.io/x}, WORKLOAD_IMAGES={busybox} -> gcr.io/x
  local scanned declared
  scanned="$(comm -23 <(printf '%s\n' "$ALL_IMAGES") <(printf '%s\n' "$WORKLOAD_IMAGES") |
    sed '/^$/d' | sort -u)"
  declared="$(yq -r "$VERSION_SELECTOR | .airgapImages // [] | .[]" "$CONFIG" 2>/dev/null |
    sed '/^$/d' | sort -u)"

  if [[ $declared != "$scanned" ]]; then
    fail_due_to_lockfile_mismatch "$scanned"
  fi

  HIDDEN_IMAGES="$scanned"
  [[ -n $HIDDEN_IMAGES ]] || return 0

  # Chart apps use extra-images.txt instead (written after save).
  chart_config_present && return 0

  local pin_namespace="${PIN_NAMESPACE:-default}"
  echo "==> Pinning $(count_lines "$HIDDEN_IMAGES") declared airgap image(s) (ns=$pin_namespace):"
  printf '%s\n' "$HIDDEN_IMAGES" | sed 's/^/      /'
  append_image_pin_deployment "$pin_namespace" "$HIDDEN_IMAGES" >>"$RAW_MANIFEST"

  # Pinned refs are now real `image:` fields; add them to the rewrite set so the
  # optional rehost-registry path stays consistent.
  WORKLOAD_IMAGES="$ALL_IMAGES"
}

# Chart apps: write the hidden images to helmrelease/extra-images.txt so the
# bundler mirrors them. Flat apps pin instead, so ensure no stale file lingers.
write_extra_images_file() {
  local extra_images_file="$MANIFESTS_DIR/$EXTRA_IMAGES_FILENAME"

  if chart_config_present && [[ -n ${HIDDEN_IMAGES:-} ]]; then
    echo "==> Writing $(count_lines "$HIDDEN_IMAGES") hidden image(s) to ${extra_images_file#"$REPO_ROOT/"}:"
    printf '%s\n' "$HIDDEN_IMAGES" | sed 's/^/      /'
    printf '%s\n' "$HIDDEN_IMAGES" >"$extra_images_file"
  else
    rm -f "$extra_images_file"
  fi
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

# Emits an inert Deployment (replicas: 0, never scheduled) that lists the hidden
# images so the airgap scanner finds and mirrors them.
# Args: $1 = namespace, $2 = newline-separated image list.
append_image_pin_deployment() {
  local namespace="$1" images="$2"
  printf '\n---\n'
  printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n'
  printf '  name: %s-airgap-image-pin\n' "$APP"
  printf '  namespace: %s\n' "$namespace"
  printf '  annotations:\n'
  printf '    nkp.nutanix.com/description: "Inert image pin (replicas: 0, never scheduled) so the airgap bundle mirrors images referenced only in env/args/ConfigMap values."\n'
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
