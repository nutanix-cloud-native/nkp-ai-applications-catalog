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

# Pipeline stages
# shellcheck disable=SC1091
{
  source "$SCRIPT_DIR/bake/args.sh"
  source "$SCRIPT_DIR/bake/config.sh"
  source "$SCRIPT_DIR/bake/render.sh"
  source "$SCRIPT_DIR/bake/airgap.sh"
  source "$SCRIPT_DIR/bake/package.sh"
  source "$SCRIPT_DIR/bake/bake.sh"
}

# Render + bake a single version end to end.
process_version() {
  load_version_config "$1"
  clone_upstream_repo
  render_kustomize_overlays
  discover_all_images
  pin_hidden_images_for_airgap
  package_and_rewrite_images
  mirror_images_to_registry

  if [[ $RENDER_ONLY == true ]]; then
    print_dry_run_summary
    return 0
  fi
  save_final_manifests
}

main() {
  parse_arguments "$@"
  check_dependencies
  load_app_config

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
