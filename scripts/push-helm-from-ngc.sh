#!/bin/sh
# Pull a Helm chart from NGC (requires NGC_API_KEY) and push to an OCI registry.
# Also generates the .catalog-source.yaml for the application.
#
# Usage:
#   NGC_API_KEY=<your-key> ./scripts/push-helm-from-ngc.sh <app-name> <chart-name> <version> <oci-registry>
#
# Example (nvidia-nim):
#   NGC_API_KEY=$NGC_API_KEY ./scripts/push-helm-from-ngc.sh nvidia-nim nim-llm 1.0.3 oci://ghcr.io/nutanix-cloud-native/charts

set -e

APP_NAME="${1:?Usage: NGC_API_KEY=<key> $0 <app-name> <chart-name> <version> <oci-registry>}"
CHART_NAME="${2:?Missing chart-name}"
VERSION="${3:?Missing version}"
OCI_REGISTRY="${4:?Missing oci-registry}"

if [ -z "${NGC_API_KEY}" ]; then
  echo "ERROR: NGC_API_KEY must be set. Get your key from https://ngc.nvidia.com/setup/api-key"
  exit 1
fi

NGC_HELM_URL="https://helm.ngc.nvidia.com/nim/charts/${CHART_NAME}-${VERSION}.tgz"

echo "==> Pulling ${CHART_NAME} ${VERSION} from NGC"
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
# Source for check-versions: NGC Helm chart (pulled with NGC_API_KEY and pushed to OCI)
ngcChart: ${CHART_NAME}
ngcUrl: https://helm.ngc.nvidia.com/nim/charts
ocipush: ${OCI_REGISTRY}

# Upstream product license (NVIDIA NGC terms — see catalog-source-license rule)
license: NVIDIA-Software-License
licenseUrl: https://docs.nvidia.com/nim/large-language-models/latest/acknowledgements.html
redistributionAllowed: true
redistributionNotes: |
  Helm chart is deployment configuration. NIM containers from nvcr.io require NGC API key.
  Users must comply with NGC terms and NVIDIA AI Enterprise for production use.
EOF

echo "==> Created $CATALOG_SOURCE"
echo "Done."
