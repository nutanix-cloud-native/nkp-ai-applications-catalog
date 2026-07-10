#!/bin/sh
# Pull a chart from a Helm repo and push it to an OCI registry.
#
# Usage:
#   ./scripts/push-helm-to-oci.sh <repo-url> <chart> <version> <oci-registry>
#
# Example (ollama):
#   ./scripts/push-helm-to-oci.sh https://otwld.github.io/ollama-helm/ ollama 1.12.3 oci://ghcr.io/nutanix-cloud-native/charts
#
# Example (vllm):
#   ./scripts/push-helm-to-oci.sh https://open-source-ai-dev.github.io/vllm-helm-chart vllm 0.1.1 oci://ghcr.io/nutanix-cloud-native/charts

set -e

REPO_URL="${1:?Usage: $0 <repo-url> <chart> <version> <oci-registry>}"
CHART="${2:?Missing chart}"
VERSION="${3:?Missing version}"
OCI_REGISTRY="${4:?Missing oci-registry}"

REPO_NAME="${CHART}-repo-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"

echo "==> Adding Helm repo: $REPO_NAME ($REPO_URL)"
helm repo add "$REPO_NAME" "$REPO_URL"
helm repo update "$REPO_NAME"

echo "==> Pulling $REPO_NAME/$CHART version $VERSION"
helm pull "$REPO_NAME/$CHART" --version "$VERSION"

TARBALL="$(find . -maxdepth 1 -name '*.tgz' | head -1)"
TARBALL="${TARBALL#./}"
if [ -z "$TARBALL" ] || [ ! -f "$TARBALL" ]; then
  echo "ERROR: helm pull did not produce a .tgz file"
  exit 1
fi

echo "==> Pushing $TARBALL to $OCI_REGISTRY"
helm push "$TARBALL" "$OCI_REGISTRY"

echo "Done."
