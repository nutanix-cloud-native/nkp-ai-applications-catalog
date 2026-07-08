# shellcheck shell=bash
# Resolve app- and version-level render inputs from bake-apps.yaml.
# Sourced by scripts/build-baked-manifests.sh.
#
# shellcheck disable=SC2154,SC2034

load_app_config() {
  REPO="$(yq -r ".apps.\"$APP\".repo // \"\"" "$CONFIG")"
  [[ -n $REPO ]] || die "App '$APP' is missing a repo in $CONFIG or is not configured"
}

# prints the configured versions.
get_app_versions() {
  yq -r ".apps.\"$APP\".versions[].version" "$CONFIG" 2>/dev/null | sed '/^$/d'
}

# selects a version block and sets VERSION, VERSION_SELECTOR, REF, OVERLAYS[],
# PIN_NAMESPACE, and derived paths.
load_version_config() {
  VERSION="$1"
  VERSION_SELECTOR=".apps.\"$APP\".versions[] | select(.version == \"$VERSION\")"

  REF="$(yq -r "$VERSION_SELECTOR | .ref // \"\"" "$CONFIG")"
  [[ -n $REF ]] || die "App '$APP' version '$VERSION' is missing a ref in $CONFIG"

  OVERLAYS=()
  while IFS= read -r overlay; do
    [[ -n $overlay ]] && OVERLAYS+=("$overlay")
  done < <(yq -r "$VERSION_SELECTOR | .overlays[]" "$CONFIG" 2>/dev/null)

  [[ ${#OVERLAYS[@]} -gt 0 ]] || die "App '$APP' version '$VERSION' has no overlays listed"

  # Namespace for the inert airgap image-pin Deployment (see airgap.sh). Explicit
  # so the pin is deterministic; defaults to "default" when unset.
  PIN_NAMESPACE="$(yq -r "$VERSION_SELECTOR | .pinNamespace // \"default\"" "$CONFIG")"

  # Per-version workspace so baking every version in one run can't clobber.
  WORK_DIR="$REPO_ROOT/.tmp/bake-$APP-$VERSION"
  CLONE_DIR="$WORK_DIR/upstream"
  RAW_MANIFEST="$WORK_DIR/raw.yaml"
  PKG_DIR="$WORK_DIR/package"
  RENDERED_FILE="$WORK_DIR/$APP.yaml"
  MANIFESTS_DIR="$REPO_ROOT/applications/$APP/$VERSION/helmrelease"
}
