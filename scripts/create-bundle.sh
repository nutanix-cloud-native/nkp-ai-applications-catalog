#!/bin/sh
# Create the catalog bundle.
#
# Usage:
#   ./scripts/create-bundle.sh <repo-root> <bundle-name> <chart-registry-base> <tag> [skip] [chart-registry]
#
# skip: comma-separated app=version to exclude, e.g. "open-webui=12.0.1,kserve=0.16.0"
# chart-registry: override Helm chart OCI base for testing (optional)

set -e

REPO_ROOT="${1:?Usage: $0 <repo-root> <bundle-name> <chart-registry-base> <tag> [skip] [chart-registry]}"
BUNDLE_NAME="${2:?Missing bundle-name}"
CHART_REGISTRY_BASE="${3:?Missing chart-registry-base}"
TAG="${4:?Missing tag}"
SKIP="${5:-}"
CHART_REGISTRY="${6:-}"
NKP_CLI="${NKP_CLI:?NKP_CLI must be set}"

# When AIRGAPPED is set (non-empty), bundle the container images and OCI
# artifacts into the tarball so it can be deployed on a disconnected cluster.
# Default (unset) keeps the lightweight connected bundle (manifests + refs).
AIRGAPPED="${AIRGAPPED:-}"

# Run "nkp create catalog-bundle" with the given args, appending the airgapped
# flags when enabled. Using a function with "set --" keeps every arg properly
# quoted (no word-splitting) while still allowing conditional extra flags.
create_bundle() {
  if [ -n "$AIRGAPPED" ]; then
    set -- "$@" --airgapped --platform linux/amd64
  fi
  "$NKP_CLI" create catalog-bundle "$@"
}

rm -f "./${BUNDLE_NAME}-${TAG}.tar"

use_custom_registry=""
if [ -n "$CHART_REGISTRY" ]; then
  use_custom_registry=1
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  repodir="$tmpdir/$BUNDLE_NAME"
  rsync -a --exclude='.git' --exclude='.cursor' "$REPO_ROOT/" "$repodir/" 2>/dev/null || cp -a "$REPO_ROOT" "$repodir"
  find "$repodir/applications" -name "*.yaml" -type f -exec sed -i.bak "s|$CHART_REGISTRY_BASE|$CHART_REGISTRY|g" {} \;
  find "$repodir/applications" -name "*.bak" -delete
else
  repodir="$REPO_ROOT"
fi

if [ -z "$SKIP" ]; then
  create_bundle --repo-dir "$repodir" --collection-tag "$TAG"
else
  apps_dir="$REPO_ROOT/applications"
  all_apps=""
  for app_dir in "$apps_dir"/*/; do
    app="$(basename "$app_dir")"
    for ver_dir in "$app_dir"*/; do
      [ -d "$ver_dir" ] || continue
      ver="$(basename "$ver_dir")"
      all_apps="${all_apps}${app}=${ver},"
    done
  done
  all_apps="${all_apps%,}"
  skip_list="$(echo "$SKIP" | tr ',' '\n' | tr -d ' ')"
  include_apps=""
  for item in $(echo "$all_apps" | tr ',' '\n'); do
    skip=0
    for s in $skip_list; do
      [ "$item" = "$s" ] && skip=1 && break
    done
    [ $skip -eq 0 ] && include_apps="${include_apps}${item},"
  done
  include_apps="${include_apps%,}"
  [ -z "$include_apps" ] && echo "No apps to bundle after skipping" && exit 1
  create_bundle --repo-dir "$repodir" --collection-tag "$TAG" --apps="$include_apps"
fi

if [ -n "$use_custom_registry" ]; then
  bundle_in_repo="$repodir/${BUNDLE_NAME}-${TAG}.tar"
  if [ -f "$bundle_in_repo" ]; then
    mv "$bundle_in_repo" "$REPO_ROOT/"
  fi
fi
