# shellcheck shell=bash
# Argument parsing and dependency/config validation for the bake pipeline.
# shellcheck disable=SC2154,SC2034

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    --app)
      APP="${2:?--app needs a value}"
      shift 2
      ;;
    --version)
      VERSION_ARG="${2:?--version needs a value}"
      shift 2
      ;;
    --config)
      CONFIG="${2:?--config needs a value}"
      shift 2
      ;;
    --registry)
      REGISTRY="${2:?--registry needs a value}"
      shift 2
      ;;
    --mirror-images)
      MIRROR_IMAGES=true
      shift
      ;;
    --render-only)
      RENDER_ONLY=true
      shift
      ;;
    *)
      die "Unknown option: $1"
      ;;
    esac
  done

  # Strip trailing slash from registry for consistent URL formatting later.
  REGISTRY="${REGISTRY%/}"
}

# Fail fast so a typo doesn't silently bake an empty manifest.
check_dependencies() {
  command -v yq >/dev/null || die "yq is required"
  command -v kustomize >/dev/null || die "kustomize is required"
  [[ -n $APP ]] || die "--app is required"
  [[ -f $CONFIG ]] || die "Config file not found: $CONFIG"
}
