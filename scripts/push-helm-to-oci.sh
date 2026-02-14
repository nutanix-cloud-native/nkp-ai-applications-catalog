#!/bin/sh
# Pull a chart from a Helm repo and push it to an OCI registry.
# Also generates the .catalog-source.yaml for the application.
#
# Usage:
#   ./scripts/push-helm-to-oci.sh <app-name> <repo-name> <repo-url> <chart> <version> <oci-registry>
#
# Example (ollama):
#   ./scripts/push-helm-to-oci.sh ollama ollama-helm https://otwld.github.io/ollama-helm/ ollama 1.12.3 oci://ghcr.io/nutanix-cloud-native/ollama-helm/ollama
#
# Example (vllm):
#   ./scripts/push-helm-to-oci.sh vllm vllm https://open-source-ai-dev.github.io/vllm-helm-chart vllm 0.1.1 oci://ghcr.io/nutanix-cloud-native/vllm

set -e

APP_NAME="${1:?Usage: $0 <app-name> <repo-name> <repo-url> <chart> <version> <oci-registry>}"
REPO_NAME="${2:?Missing repo-name}"
REPO_URL="${3:?Missing repo-url}"
CHART="${4:?Missing chart}"
VERSION="${5:?Missing version}"
OCI_REGISTRY="${6:?Missing oci-registry}"

echo "==> Adding Helm repo: $REPO_NAME ($REPO_URL)"
helm repo add "$REPO_NAME" "$REPO_URL"
helm repo update "$REPO_NAME"

echo "==> Pulling $REPO_NAME/$CHART version $VERSION"
helm pull "$REPO_NAME/$CHART" --version "$VERSION"

TARBALL="${CHART}-${VERSION}.tgz"
if [ ! -f "$TARBALL" ]; then
  echo "ERROR: Expected tarball $TARBALL not found"
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
# Source for check-versions: Helm repo (pulled and pushed to OCI during add-app)
helmrepo: ${REPO_NAME}/${CHART}
helmrepoUrl: ${REPO_URL}
ocipush: ${OCI_REGISTRY}
EOF

echo "==> Created $CATALOG_SOURCE"
echo "Done."
