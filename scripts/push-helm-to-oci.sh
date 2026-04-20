#!/bin/sh
# Pull a chart from a Helm repo and push it to an OCI registry.
# Also generates the .catalog-source.yaml for the application.
#
# Usage:
#   ./scripts/push-helm-to-oci.sh <app-name> <repo-name> <repo-url> <chart> <version> <oci-registry>
#
# Example (ollama):
#   ./scripts/push-helm-to-oci.sh ollama ollama-helm https://otwld.github.io/ollama-helm/ ollama 1.12.3 oci://ghcr.io/nutanix-cloud-native/charts
#
# Example (vllm):
#   ./scripts/push-helm-to-oci.sh vllm vllm https://open-source-ai-dev.github.io/vllm-helm-chart vllm 0.1.1 oci://ghcr.io/nutanix-cloud-native/charts

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
# Create a temporary directory to ensure clean download
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
helm pull "$REPO_NAME/$CHART" --version "$VERSION"

# Chart tarball name may vary (e.g. coder produces coder_helm_2.30.2.tgz)
# Try standard format first
TARBALL="${CHART}-${VERSION}.tgz"
if [ ! -f "$TARBALL" ]; then
  # Find any .tgz file with the version in the name
  TARBALL="$(find . -maxdepth 1 -name '*'"${VERSION}"'.tgz' 2>/dev/null | head -1)"
  TARBALL="${TARBALL#./}" # Remove leading ./
fi
if [ -z "$TARBALL" ] || [ ! -f "$TARBALL" ]; then
  echo "ERROR: Expected tarball ${CHART}-${VERSION}.tgz (or *${VERSION}.tgz) not found"
  echo "Available files:"
  ls -la ./*.tgz 2>/dev/null || echo "  No .tgz files found"
  exit 1
fi

echo "==> Validating chart: $TARBALL"

# Security validation 1: Filename checks
if ! echo "$TARBALL" | grep -qi "$CHART"; then
  echo "ERROR: Downloaded file '$TARBALL' does not contain expected chart name '$CHART'"
  echo "This is a security check to prevent pushing wrong charts."
  ls -la ./*.tgz 2>/dev/null || true
  exit 1
fi

if ! echo "$TARBALL" | grep -q "$VERSION"; then
  echo "ERROR: Downloaded file '$TARBALL' does not contain expected version '$VERSION'"
  echo "This is a security check to prevent pushing wrong versions."
  ls -la ./*.tgz 2>/dev/null || true
  exit 1
fi

# Security validation 2: Chart.yaml metadata checks
echo "==> Extracting Chart.yaml for metadata validation"
tar -xzf "$TARBALL" --wildcards '*/Chart.yaml' 2>/dev/null || {
  echo "ERROR: Failed to extract Chart.yaml from $TARBALL"
  exit 1
}

# Find the top-level Chart.yaml (shortest path = main chart, not dependencies)
# Dependencies are typically in */charts/*/Chart.yaml, main chart is in */Chart.yaml
CHART_YAML=$(find . -name 'Chart.yaml' -type f | awk '{print length, $0}' | sort -n | head -1 | cut -d' ' -f2-)
if [ -z "$CHART_YAML" ] || [ ! -f "$CHART_YAML" ]; then
  echo "ERROR: Chart.yaml not found in tarball"
  exit 1
fi

echo "==> Using Chart.yaml: $CHART_YAML"

# Extract and validate chart metadata using grep/awk for POSIX compatibility
CHART_NAME_FROM_YAML=$(grep '^name:' "$CHART_YAML" | awk '{print $2}' | tr -d '"' | tr -d "'" | tr -d '\r')
CHART_VERSION_FROM_YAML=$(grep '^version:' "$CHART_YAML" | awk '{print $2}' | tr -d '"' | tr -d "'" | tr -d '\r')

echo "==> Chart metadata from Chart.yaml:"
echo "  name: $CHART_NAME_FROM_YAML"
echo "  version: $CHART_VERSION_FROM_YAML"

# Validate chart name matches
if [ "$CHART_NAME_FROM_YAML" != "$CHART" ]; then
  echo "ERROR: Chart name mismatch!"
  echo "  Expected: $CHART"
  echo "  Got from Chart.yaml: $CHART_NAME_FROM_YAML"
  echo "This indicates the wrong chart was downloaded."
  exit 1
fi

# Validate chart version matches
if [ "$CHART_VERSION_FROM_YAML" != "$VERSION" ]; then
  echo "ERROR: Chart version mismatch!"
  echo "  Expected: $VERSION"
  echo "  Got from Chart.yaml: $CHART_VERSION_FROM_YAML"
  echo "This indicates the wrong version was downloaded."
  exit 1
fi

echo "✓ Security validation passed:"
echo "  - Chart name '$CHART' matches Chart.yaml"
echo "  - Chart version '$VERSION' matches Chart.yaml"
echo "  - Filename contains chart name and version"

echo "==> Pushing $TARBALL to $OCI_REGISTRY"
helm push "$TARBALL" "$OCI_REGISTRY"

echo "==> Cleaning up"
cd - >/dev/null
rm -rf "$TMPDIR"

# Generate .catalog-source.yaml
CATALOG_SOURCE="applications/${APP_NAME}/.catalog-source.yaml"
mkdir -p "applications/${APP_NAME}"

cat >"$CATALOG_SOURCE" <<EOF
# Source for check-versions: Helm repo (pulled and pushed to OCI during add-app)
helmrepo: ${REPO_NAME}/${CHART}
helmrepoUrl: ${REPO_URL}
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
