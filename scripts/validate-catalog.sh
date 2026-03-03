#!/bin/sh
# Validate the catalog repository. When CHART_REGISTRY is set, replaces chart URLs
# in a temp copy before validating (same pattern as create-bundle).
#
# Usage:
#   CHART_REGISTRY=oci://ghcr.io/deepak-muley/charts ./scripts/validate-catalog.sh
#   ./scripts/validate-catalog.sh
#
# Requires: NKP_CLI, REPO_ROOT (or run from repo root)

set -e

REPO_ROOT="${REPO_ROOT:-$(pwd)}"
CHART_REGISTRY_BASE="${CHART_REGISTRY_BASE:-oci://ghcr.io/nutanix-cloud-native/charts}"
CHART_REGISTRY="${CHART_REGISTRY:-}"
NKP_CLI="${NKP_CLI:?NKP_CLI must be set}"

if [ -n "$CHART_REGISTRY" ]; then
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  repodir="$tmpdir/repo"
  cp -a "$REPO_ROOT" "$repodir"
  find "$repodir/applications" -name "*.yaml" -type f -exec sed -i.bak "s|$CHART_REGISTRY_BASE|$CHART_REGISTRY|g" {} \;
  find "$repodir/applications" -name "*.bak" -delete
  "$NKP_CLI" validate catalog-repository -v=3 --repo-dir="$repodir"
else
  "$NKP_CLI" validate catalog-repository -v=3 --repo-dir="$REPO_ROOT"
fi
