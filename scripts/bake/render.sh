# shellcheck shell=bash
# Clone the pinned upstream, render its Kustomize overlays into one raw manifest,
# and discover the images it references.
# shellcheck disable=SC2154,SC2034

clone_upstream_repo() {
  echo "==> [$APP $VERSION] Cloning upstream repository..."
  rm -rf "$CLONE_DIR" && mkdir -p "$WORK_DIR"
  git clone --depth 1 --branch "$REF" "$REPO" "$CLONE_DIR" >/dev/null 2>&1
}

# Flattens the remote Kustomize structure into a single static file, bypassing
# Flux's inability to resolve parent ("../") paths in air-gaps.
render_kustomize_overlays() {
  : >"$RAW_MANIFEST" # start from an empty file
  for overlay in "${OVERLAYS[@]}"; do
    echo "==> Rendering overlay: $overlay"
    # Separate documents with a YAML "---" once there's already content.
    [[ -s $RAW_MANIFEST ]] && printf '\n---\n' >>"$RAW_MANIFEST"

    # LoadRestrictionsRootOnly matches the airgap parser's strict requirements.
    kustomize build --load-restrictor LoadRestrictionsRootOnly \
      "$CLONE_DIR/$overlay" >>"$RAW_MANIFEST"
  done
}

# Populates two image lists from the rendered manifest:
#   WORKLOAD_IMAGES - the values of real `image:` fields (what pods actually run).
#   ALL_IMAGES      - those PLUS any registry-qualified ref found ANYWHERE in the
#                     text (env vars, args, ConfigMap values, ...). The extra refs
#                     are exactly the ones the airgap scanner would otherwise miss.
discover_all_images() {
  WORKLOAD_IMAGES="$(get_image_field_values)"
  ALL_IMAGES="$(printf '%s\n%s\n' "$WORKLOAD_IMAGES" "$(get_registry_qualified_refs)" |
    sed '/^$/d' | sort -u)"
}

# Extracts the value after each `image:` key, e.g. "image: nginx:1.25" -> nginx:1.25.
get_image_field_values() {
  grep -oE 'image:[[:space:]]*[^[:space:]]+' "$RAW_MANIFEST" |
    sed 's/image:[[:space:]]*//' |
    tr -d '"' |
    sort -u
}

# Finds every "<known-registry>/path[:tag]" token anywhere in the manifest, so we
# also catch images buried in non-image fields (env/args/ConfigMap data).
get_registry_qualified_refs() {
  local known_registries='ghcr\.io|gcr\.io|quay\.io|docker\.io|registry\.k8s\.io|mcr\.microsoft\.com'
  grep -oE "(${known_registries})/[a-zA-Z0-9._/-]+(:[a-zA-Z0-9._-]+)?" "$RAW_MANIFEST" | sort -u
}
