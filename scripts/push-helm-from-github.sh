#!/bin/sh
# Package a Helm chart from a GitHub repo and push to an OCI registry.
# Use when the chart is in a Git repo but not published to a Helm repository.
#
# Usage:
#   ./scripts/push-helm-from-github.sh <app-name> <git-url> <chart-path> <version> <oci-registry>
#
# Example (sim):
#   ./scripts/push-helm-from-github.sh sim https://github.com/simstudioai/sim.git helm/sim 0.1.0 oci://ghcr.io/nutanix-cloud-native/charts

set -e

APP_NAME="${1:?Usage: $0 <app-name> <git-url> <chart-path> <version> <oci-registry>}"
GIT_URL="${2:?Missing git-url}"
CHART_PATH="${3:?Missing chart-path}"
VERSION="${4:?Missing version}"
OCI_REGISTRY="${5:?Missing oci-registry}"

# Extract chart name from path (e.g. helm/sim -> sim)
CHART_NAME="$(basename "$CHART_PATH")"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "==> Cloning $GIT_URL"
git clone --depth 1 "$GIT_URL" "$TMPDIR/repo"

echo "==> Packaging $CHART_PATH"
helm package "$TMPDIR/repo/$CHART_PATH" --version "$VERSION" -d "$TMPDIR"

TARBALL="$TMPDIR/${CHART_NAME}-${VERSION}.tgz"
if [ ! -f "$TARBALL" ]; then
  echo "ERROR: Expected tarball ${CHART_NAME}-${VERSION}.tgz not found"
  ls -la "$TMPDIR"
  exit 1
fi

echo "==> Pushing $TARBALL to $OCI_REGISTRY"
helm push "$TARBALL" "$OCI_REGISTRY"

# Generate .catalog-source.yaml
CATALOG_SOURCE="applications/${APP_NAME}/.catalog-source.yaml"
mkdir -p "applications/${APP_NAME}"

cat >"$CATALOG_SOURCE" <<EOF
# Source for check-versions: Git (packaged and pushed to OCI during add-app)
giturl: ${GIT_URL}
chartpath: ${CHART_PATH}
ocipush: ${OCI_REGISTRY}

# Upstream product license (required — see catalog-source-license rule in AGENTS.md)
# Fill in from the upstream project's public LICENSE file. If redistributionAllowed is false, do not add to catalog.
license: ""
licenseUrl: ""
redistributionAllowed: true
redistributionNotes: ""
EOF

echo "==> Created $CATALOG_SOURCE"
echo "Done."
