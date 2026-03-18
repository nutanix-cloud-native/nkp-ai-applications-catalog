#!/bin/sh
# Pull a Helm chart from NGC DOCA team (requires NGC_API_KEY) and push to an OCI registry.
# Also generates the .catalog-source.yaml for the application.
#
# Usage:
#   NGC_API_KEY=<your-key> ./scripts/push-helm-from-ngc-doca.sh <app-name> <chart-name> <version> <oci-registry>
#
# Example (nvidia-doca):
#   NGC_API_KEY=$NGC_API_KEY ./scripts/push-helm-from-ngc-doca.sh nvidia-doca dpu-networking 25.10.1 oci://ghcr.io/nutanix-cloud-native/charts

set -e

APP_NAME="${1:?Usage: NGC_API_KEY=<key> $0 <app-name> <chart-name> <version> <oci-registry>}"
CHART_NAME="${2:?Missing chart-name}"
VERSION="${3:?Missing version}"
OCI_REGISTRY="${4:?Missing oci-registry}"

if [ -z "${NGC_API_KEY}" ]; then
  echo "ERROR: NGC_API_KEY must be set. Get your key from https://ngc.nvidia.com/setup/api-key"
  exit 1
fi

NGC_HELM_URL="https://helm.ngc.nvidia.com/doca/charts/${CHART_NAME}-${VERSION}.tgz"

echo "==> Pulling ${CHART_NAME} ${VERSION} from NGC DOCA"
helm pull "$NGC_HELM_URL" --username='$oauthtoken' --password="$NGC_API_KEY"

TARBALL="${CHART_NAME}-${VERSION}.tgz"
if [ ! -f "$TARBALL" ]; then
  echo "ERROR: Expected tarball $TARBALL not found"
  ls -la ./*.tgz 2>/dev/null || true
  exit 1
fi

echo "==> Pushing $TARBALL to $OCI_REGISTRY"
helm push "$TARBALL" "$OCI_REGISTRY"

echo "==> Cleaning up $TARBALL"
rm -f "$TARBALL"

# Generate .catalog-source.yaml
CATALOG_SOURCE="applications/${APP_NAME}/.catalog-source.yaml"
mkdir -p "applications/${APP_NAME}"

cat >"$CATALOG_SOURCE" <<EOF
# Source for check-versions: NGC DOCA Helm chart (pulled with NGC_API_KEY and pushed to OCI)
ngcChart: ${CHART_NAME}
ngcUrl: https://helm.ngc.nvidia.com/doca/charts
ocipush: ${OCI_REGISTRY}

# Upstream product license (NVIDIA DOCA Platform — Apache-2.0)
license: Apache-2.0
licenseUrl: https://github.com/NVIDIA/doca-platform/blob/main/LICENSE
redistributionAllowed: true
redistributionNotes: |
  DOCA Platform is Apache-2.0 licensed. Helm chart is deployment configuration.
  Users must comply with NGC terms for container images from nvcr.io.
EOF

echo "==> Created $CATALOG_SOURCE"
echo "Done."
