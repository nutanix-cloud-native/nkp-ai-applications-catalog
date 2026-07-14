# shellcheck shell=bash
# Package the rendered manifest and, when --registry is set, rewrite every image
# reference onto that rehost registry (and optionally mirror the bits there).
# shellcheck disable=SC2154,SC2034

# Rewrites one image reference onto $REGISTRY while preserving its repo path.
# Docker Hub is the awkward case: refs like "busybox" or "argoproj/argoexec"
# carry no registry host, and Docker implicitly expands a bare name to
# "library/<name>". We reproduce that so the rehosted path stays stable.
get_registry_image_path() {
  local image="$1"
  local first_part="${image%%/*}" # text before the first '/', or the whole ref
  local image_path

  # The ref has an explicit registry host only when its first segment looks like
  # a hostname: it contains a dot, a ":port", or is literally "localhost".
  if [[ $first_part == *.* || $first_part == *:* || $first_part == "localhost" ]]; then
    image_path="${image#*/}" # drop the registry host, keep the rest
  elif [[ $image == */* ]]; then
    image_path="$image" # Docker Hub "user/repo": keep as-is
  else
    image_path="library/$image" # Docker Hub bare name: "busybox" -> "library/busybox"
  fi

  echo "$REGISTRY/$image_path"
}

# Backslash-escape every character that is special inside a sed regex, so an
# image ref like "gcr.io/foo" is matched literally (the "." won't act as
# "any char"). The bracket class covers: ] [ ^ $ . * / and backslash itself.
# A "]" has to be the first member of the class to be read as a literal "]".
# Example: "gcr.io/foo" -> "gcr\.io/foo"
escape_for_regex() {
  printf '%s' "$1" | sed 's/[][^$.*/\\]/\\&/g'
}

# Writes the final manifest to RENDERED_FILE. With no --registry it's just the
# raw render; with --registry every image is repointed at the rehost registry.
package_and_rewrite_images() {
  rm -rf "$PKG_DIR" && mkdir -p "$PKG_DIR"
  cp "$RAW_MANIFEST" "$PKG_DIR/resources.yaml"

  create_kustomization_file
  kustomize build "$PKG_DIR" >"$RENDERED_FILE"

  [[ -n $REGISTRY ]] || return 0
  rewrite_hidden_image_refs
}

# Copies patch files into the packaging dir (kustomize's RootOnly load-restrictor
# forbids paths outside the root) and echoes the `patches:` block. Each patch gets
# a kind+name target so matching survives the namespace transformer, which runs
# after patching (a bare metadata.namespace would otherwise mismatch).
stage_patches_block() {
  [[ ${#PATCHES[@]} -gt 0 ]] || return 0
  echo "patches:"
  local patch base kind name
  for patch in "${PATCHES[@]}"; do
    base="$(basename "$patch")"
    cp "$REPO_ROOT/$patch" "$PKG_DIR/$base"
    kind="$(yq -r '.kind // ""' "$REPO_ROOT/$patch")"
    name="$(yq -r '.metadata.name // ""' "$REPO_ROOT/$patch")"
    echo "  - path: $base"
    if [[ -n $kind && -n $name ]]; then
      echo "    target:"
      echo "      kind: $kind"
      echo "      name: $name"
    fi
  done
}

# Builds the packaging kustomization.
create_kustomization_file() {
  {
    echo "apiVersion: kustomize.config.k8s.io/v1beta1"
    echo "kind: Kustomization"
    # Rewrites metadata.namespace + RBAC subjects (see config.sh NAMESPACE).
    [[ -n $NAMESPACE ]] && echo "namespace: $NAMESPACE"
    echo "resources:"
    echo "  - resources.yaml"
    stage_patches_block
    if [[ -n $REGISTRY ]]; then
      echo "images:"
      # WORKLOAD_IMAGES may have been widened to ALL_IMAGES by the airgap pin
      # step (see collect_hidden_images_for_airgap in airgap.sh), so this list
      # can include the pinned "hidden" refs too.
      while IFS= read -r image; do
        [[ -z $image ]] && continue
        local image_name="${image%:*}" # strip ":tag" only; keep any "host:port"
        echo "  - name: $image_name"
        echo "    newName: $(get_registry_image_path "$image_name")"
      done <<<"$WORKLOAD_IMAGES"
    fi
  } >"$PKG_DIR/kustomization.yaml"
}

# rewrite image refs that kustomize won't touch (env vars, args,
# ConfigMap values).
rewrite_hidden_image_refs() {
  while IFS= read -r image; do
    [[ -z $image ]] && continue
    local image_name="${image%:*}"
    # Only rewrite refs with an explicit registry host (a dot before the first
    # slash, e.g. "gcr.io/foo"). Bare Docker Hub names like "busybox" were
    # already handled by kustomize's images: transformer, so skip them here.
    [[ $image_name != *.*/* ]] && continue

    local escaped_name
    escaped_name="$(escape_for_regex "$image_name")"
    local new_image_path
    new_image_path="$(get_registry_image_path "$image_name")"

    # Repoint a hidden image ref onto $REGISTRY, but only when it sits at a real
    # word boundary, so "gcr.io/foo" is rewritten while "notgcr.io/foo" is not.
    # The leading group is "start-of-line or a non-ref char"; the trailing group
    # is one of : @ " ' space ) or end-of-line. \1 and \2 put those boundaries
    # back untouched.
    # Example: 'value: "gcr.io/foo:v1"' -> 'value: "myreg/gcr.io/foo:v1"'
    sed -i.bak -E "s#(^|[^A-Za-z0-9._/@-])${escaped_name}([:@\"' )]|\$)#\1${new_image_path}\2#g" "$RENDERED_FILE"
  done <<<"$ALL_IMAGES"
  rm -f "${RENDERED_FILE}.bak"
}

mirror_images_to_registry() {
  [[ $MIRROR_IMAGES == true ]] || return 0
  [[ -n $REGISTRY ]] || die "--mirror-images requires --registry"

  echo "==> Mirroring images to $REGISTRY"
  while IFS= read -r image; do
    [[ -z $image ]] && continue
    local target_image
    target_image="$(get_registry_image_path "$image")"
    echo "    Copying: $image -> $target_image"
    crane copy "$image" "$target_image"
  done <<<"$ALL_IMAGES"
}
