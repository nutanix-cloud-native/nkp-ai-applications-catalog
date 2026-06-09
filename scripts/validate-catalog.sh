#!/bin/sh
# Validate the catalog repository. When CHART_REGISTRY is set, replaces chart URLs
# in a temp copy before validating (same pattern as create-bundle).
#
# Usage:
#   ./scripts/validate-catalog.sh [skip]
#   CHART_REGISTRY=oci://ghcr.io/deepak-muley/charts ./scripts/validate-catalog.sh
#
# skip: comma-separated app=version to exclude, e.g. "katib=0.19.0,kserve=0.16.0"
# Requires: NKP_CLI, REPO_ROOT (or run from repo root)

set -e

REPO_ROOT="${REPO_ROOT:-$(pwd)}"
CHART_REGISTRY_BASE="${CHART_REGISTRY_BASE:-oci://ghcr.io/nutanix-cloud-native/charts}"
CHART_REGISTRY="${CHART_REGISTRY:-}"
NKP_CLI="${NKP_CLI:?NKP_CLI must be set}"
SKIP="${1:-}"

if [ -n "$CHART_REGISTRY" ]; then
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  repodir="$tmpdir/repo"
  cp -a "$REPO_ROOT" "$repodir"
  find "$repodir/applications" -name "*.yaml" -type f -exec sed -i.bak "s|$CHART_REGISTRY_BASE|$CHART_REGISTRY|g" {} \;
  find "$repodir/applications" -name "*.bak" -delete
else
  repodir="$REPO_ROOT"
fi

if [ -z "$SKIP" ]; then
  "$NKP_CLI" validate catalog-repository -v=3 --repo-dir="$repodir"
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

  if [ -z "$include_apps" ]; then
    echo "No apps to validate after skipping"
    exit 0
  fi

  echo "Skipping: $SKIP"
  echo "Validating: $include_apps"
  "$NKP_CLI" validate catalog-repository -v=3 --repo-dir="$repodir" --apps="$include_apps"
fi
