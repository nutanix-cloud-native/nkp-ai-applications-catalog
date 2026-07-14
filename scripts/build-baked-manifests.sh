#!/usr/bin/env bash
# Renders complex Kustomize apps into a single, self-contained manifest.
# Enables air-gapped deployments for apps (like Kubeflow) that rely on
# remote bases which Flux's load-restrictor normally blocks.
#
# shellcheck disable=SC2034

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults; parse_arguments and the load_* helpers populate the rest.
CONFIG="$SCRIPT_DIR/bake-apps.yaml"
APP=""
VERSION_ARG="" # optional --version filter; empty means "all configured versions"
REGISTRY=""
MIRROR_IMAGES=false
RENDER_ONLY=false

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# --- Shared pipeline globals ---------------------------------------------------
# The stage functions below live in separate files and talk to each other through
# these globals rather than return values. This block is the one place that lists
# every global, who sets it, and who reads it. Because the stages are sourced
# fragments, each fragment keeps `# shellcheck disable=SC2154,SC2034` (shellcheck
# can't see cross-file assignments); this map is the human-readable substitute.
#
# Set by parse_arguments (args.sh), from CLI flags:
#   APP VERSION_ARG CONFIG REGISTRY MIRROR_IMAGES RENDER_ONLY
# Set by load_app_config / load_version_config (config.sh), per app+version:
#   REPO VERSION VERSION_SELECTOR REF OVERLAYS[] PIN_NAMESPACE NAMESPACE PATCHES[]
#   WORK_DIR CLONE_DIR RAW_MANIFEST PKG_DIR RENDERED_FILE MANIFESTS_DIR
# Set by discover_all_images (render.sh):
#   WORKLOAD_IMAGES  - values of real `image:` fields
#   ALL_IMAGES       - WORKLOAD_IMAGES plus refs hidden in env/args/ConfigMaps
# Set by collect_hidden_images_for_airgap (airgap.sh):
#   HIDDEN_IMAGES    - refs only found outside `image:` fields
#   NOTE: for flat apps this step also WIDENS WORKLOAD_IMAGES to ALL_IMAGES, which
#   package.sh reads later. That reassignment is the one cross-stage mutation.
# -----------------------------------------------------------------------------

# Pipeline stages
# shellcheck disable=SC1091
{
  source "$SCRIPT_DIR/bake/args.sh"
  source "$SCRIPT_DIR/bake/config.sh"
  source "$SCRIPT_DIR/bake/render.sh"
  source "$SCRIPT_DIR/bake/airgap.sh"
  source "$SCRIPT_DIR/bake/package.sh"
  source "$SCRIPT_DIR/bake/parameterize.sh"
  source "$SCRIPT_DIR/bake/bake.sh"
}

# Render + bake a single version end to end. The trailing comments show which
# sourced file each stage function lives in, so you don't have to grep for it.
process_version() {
  load_version_config "$1"          # config.sh
  clone_upstream_repo               # render.sh
  render_kustomize_overlays         # render.sh
  discover_all_images               # render.sh
  collect_hidden_images_for_airgap  # airgap.sh
  package_and_rewrite_images        # package.sh
  mirror_images_to_registry         # package.sh

  if [[ $RENDER_ONLY == true ]]; then
    print_dry_run_summary           # bake.sh
    return 0
  fi

  # Chart-enabled apps emit a Helm chart (charts/<app>/) for a configOverrides
  # surface; others keep the flat-manifest layout.
  if chart_config_present; then     # parameterize.sh
    generate_chart                  # parameterize.sh
  else
    save_final_manifests            # bake.sh
  fi

  # Write hidden images to extra-images.txt for chart apps (no-op for flat apps,
  # which pin instead). Runs after save so the file lands beside the artifacts.
  write_extra_images_file           # airgap.sh
}

main() {
  parse_arguments "$@"   # args.sh
  check_dependencies     # args.sh
  load_app_config        # config.sh

  # --version bakes just that version.
  local versions
  if [[ -n $VERSION_ARG ]]; then
    get_app_versions | grep -qxF "$VERSION_ARG" ||
      die "$APP has no version '$VERSION_ARG' in $CONFIG"
    versions="$VERSION_ARG"
  else
    versions="$(get_app_versions)"
  fi
  [[ -n $versions ]] || die "$APP has no versions in $CONFIG"

  while IFS= read -r v; do
    [[ -z $v ]] && continue
    process_version "$v"
  done <<<"$versions"
}

main "$@"
