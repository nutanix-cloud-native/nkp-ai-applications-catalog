#!/bin/sh
# Package a local Helm chart and push to OCI registry.
# Use for charts that are not published to a Helm repo (e.g. custom charts).
#
# Usage:
#   ./scripts/push-local-chart-to-oci.sh <app-name> <chart-path> <version> <oci-registry>
#
# Example (crewai):
#   ./scripts/push-local-chart-to-oci.sh crewai charts/crewai 1.0.0 oci://ghcr.io/nutanix-cloud-native/charts

set -e

APP_NAME="${1:?Usage: $0 <app-name> <chart-path> <version> <oci-registry>}"
CHART_PATH="${2:?Missing chart-path}"
VERSION="${3:?Missing version}"
OCI_REGISTRY="${4:?Missing oci-registry}"

echo "==> Packaging $CHART_PATH"
helm package "$CHART_PATH" --version "$VERSION"

TARBALL="${APP_NAME}-${VERSION}.tgz"
if [ ! -f "$TARBALL" ]; then
  TARBALL="$(find . -maxdepth 1 -name '*-'"${VERSION}"'.tgz' 2>/dev/null | head -1)"
fi
if [ -z "$TARBALL" ] || [ ! -f "$TARBALL" ]; then
  echo "ERROR: Expected tarball ${APP_NAME}-${VERSION}.tgz not found"
  exit 1
fi

echo "==> Pushing $TARBALL to $OCI_REGISTRY"
helm push "$TARBALL" "$OCI_REGISTRY"

echo "==> Cleaning up $TARBALL"
rm -f "$TARBALL"

# Generate .catalog-source.yaml (local chart - no helmrepo)
CATALOG_SOURCE="applications/${APP_NAME}/.catalog-source.yaml"
mkdir -p "applications/${APP_NAME}"

cat >"$CATALOG_SOURCE" <<EOF
# Source for check-versions: Local chart (no upstream Helm repo)
# Chart is packaged from charts/${APP_NAME}/ and pushed to OCI
helmrepo: ""
helmrepoUrl: ""
ocipush: ${OCI_REGISTRY}

# Upstream product license (CrewAI framework is MIT)
license: "MIT"
licenseUrl: "https://github.com/crewAIInc/crewAI/blob/master/LICENSE"
redistributionAllowed: true
redistributionNotes: |
  Use, reproduction, distribution, modification permitted. Retain copyright notice.
  See licenseUrl for full terms.
EOF

echo "==> Created $CATALOG_SOURCE"
echo "Done."
