#!/usr/bin/env bash
# Mirror container images from Kubeflow Kustomize apps to a private registry.
#
# Prerequisites:
#   - kustomize (kubectl kustomize or kustomize)
#   - yq (for parsing config)
#   - For --push: crane (recommended) or docker
#     - crane: go install github.com/google/go-containerregistry/cmd/crane@latest
#     - docker: must be logged in to target registry
#
# Usage:
#   ./scripts/mirror-kubeflow-images.sh --list-only
#   ./scripts/mirror-kubeflow-images.sh --list-only --app kubeflow-central-dashboard
#   ./scripts/mirror-kubeflow-images.sh --push ghcr.io/deepak-muley
#   ./scripts/mirror-kubeflow-images.sh --push ghcr.io/deepak-muley --app katib
#
# Override path for an app (useful for testing custom kustomize paths):
#   PATH_OVERRIDE=./applications/centraldashboard/overlays/oauth2-proxy \
#     ./scripts/mirror-kubeflow-images.sh --list-only --app kubeflow-central-dashboard
#
# Write full image list to file:
#   ./scripts/mirror-kubeflow-images.sh --list-only --output-file images.txt
#
# Config: scripts/kubeflow-kustomize-apps.yaml

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$SCRIPT_DIR/kubeflow-kustomize-apps.yaml"
WORK_DIR="${WORK_DIR:-$REPO_ROOT/.tmp/kubeflow-mirror}"
TARGET_REGISTRY=""
LIST_ONLY=false
APP_FILTER=""
OUTPUT_FILE=""

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
  --list-only)
    LIST_ONLY=true
    shift
    ;;
  --output-file)
    OUTPUT_FILE="${2:?--output-file requires path}"
    shift 2
    ;;
  --push)
    TARGET_REGISTRY="${2:?--push requires registry (e.g. ghcr.io/deepak-muley)}"
    shift 2
    ;;
  --app)
    APP_FILTER="${2:?--app requires app name}"
    shift 2
    ;;
  *)
    echo "Unknown option: $1"
    echo "Usage: $0 [--list-only] [--push REGISTRY] [--app APP_NAME]"
    exit 1
    ;;
  esac
done

if [[ -z $TARGET_REGISTRY && $LIST_ONLY != "true" ]]; then
  echo "Usage: $0 --list-only | $0 --push REGISTRY [--app APP_NAME]"
  exit 1
fi

# Strip trailing slash from registry
TARGET_REGISTRY="${TARGET_REGISTRY%/}"

# Extract images from kustomize build output
extract_images() {
  kustomize build "$1" 2>/dev/null | grep -oE 'image:\s*[^[:space:]]+' | sed 's/image:[[:space:]]*//' | sort -u
}

# Map source image to target (preserve path under new registry)
# e.g. ghcr.io/kubeflow/katib/katib-controller:v0.19.0 -> ghcr.io/deepak-muley/kubeflow/katib/katib-controller:v0.19.0
map_to_target() {
  local img="$1"
  local reg="$2"
  # Remove registry part, keep repo:tag
  # ghcr.io/kubeflow/katib/katib-controller:v0.19.0 -> kubeflow/katib/katib-controller:v0.19.0
  local rest="${img#*/}"
  echo "${reg}/${rest}"
}

# Push image using crane or docker
push_image() {
  local src="$1"
  local dst="$2"
  if command -v crane &>/dev/null; then
    crane copy "$src" "$dst"
  elif command -v docker &>/dev/null; then
    docker pull "$src"
    docker tag "$src" "$dst"
    docker push "$dst"
  else
    echo "ERROR: Need crane or docker to push. Install: go install github.com/google/go-containerregistry/cmd/crane@latest"
    exit 1
  fi
}

# Process one app
process_app() {
  local app="$1"
  local repo="$2"
  local ref="$3"
  local path="$4"

  # PATH_OVERRIDE overrides the path for the current app
  if [[ -n ${PATH_OVERRIDE:-} ]]; then
    path="$PATH_OVERRIDE"
  fi

  local clone_dir
  clone_dir="$WORK_DIR/$(echo "$repo" | sed 's|https://||;s|/|_|g')"
  if [[ ! -d $clone_dir ]]; then
    echo "==> Cloning $repo (ref=$ref) into $clone_dir"
    git clone --depth 1 --branch "$ref" "$repo" "$clone_dir" 2>/dev/null ||
      git clone --depth 1 "$repo" "$clone_dir" && cd "$clone_dir" && git checkout "$ref" 2>/dev/null
    cd - >/dev/null
  fi

  # Normalize path: ./foo/bar -> foo/bar
  local path_norm="${path#./}"
  local kustomize_path="$clone_dir/$path_norm"
  if [[ ! -d $kustomize_path ]]; then
    echo "ERROR: Path not found: $kustomize_path"
    return 1
  fi

  echo "==> $app ($path)"
  local images
  images=$(extract_images "$kustomize_path")
  if [[ -z $images ]]; then
    echo "    (no images found)"
    return 0
  fi

  while IFS= read -r img; do
    [[ -z $img ]] && continue
    echo "    $img"
    if [[ -n $OUTPUT_FILE ]]; then
      echo "$img" >>"$OUTPUT_FILE"
    fi
    if [[ -n $TARGET_REGISTRY ]]; then
      local dst
      dst=$(map_to_target "$img" "$TARGET_REGISTRY")
      echo "      -> $dst"
      push_image "$img" "$dst"
    fi
  done <<<"$images"
}

# Main
mkdir -p "$WORK_DIR"
[[ -n $OUTPUT_FILE ]] && : >"$OUTPUT_FILE"
echo "Config: $CONFIG"
echo "Work dir: $WORK_DIR"
[[ -n $OUTPUT_FILE ]] && echo "Output file: $OUTPUT_FILE"
echo ""

# Ensure we're in repo root for relative paths
cd "$REPO_ROOT"

# Validate APP_FILTER exists if set
if [[ -n $APP_FILTER ]]; then
  yq -e ".apps | to_entries | map(select(.key == \"$APP_FILTER\")) | from_entries" "$CONFIG" >/dev/null 2>&1 || {
    echo "ERROR: App '$APP_FILTER' not found in config"
    exit 1
  }
fi

for app in $(yq -r '.apps | keys[]' "$CONFIG"); do
  [[ -n $APP_FILTER && $app != "$APP_FILTER" ]] && continue

  repo=$(yq -r ".apps[\"$app\"].repo" "$CONFIG")
  ref=$(yq -r ".apps[\"$app\"].ref" "$CONFIG")
  path=$(yq -r ".apps[\"$app\"].path" "$CONFIG")

  process_app "$app" "$repo" "$ref" "$path"
  echo ""
done

echo "Done."
