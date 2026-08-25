#!/bin/sh
# Create a catalog bundle and push it to OCI.
#
# Usage:
#   ./scripts/create_and_push_bundle.sh <bundle-file>
#
# Example:
#   ./scripts/create_and_push_bundle.sh nkp-ai-applications-catalog-v1.0.15.tar

set -eu

BUNDLE="${1:?Usage: $0 <bundle-file>}"
COLLECTION_TAG="v1.0.15"
REGISTRY="oci://ghcr.io/marktanix/"

REPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# nkp reuses an existing bundle file instead of rebuilding
rm -f "$BUNDLE"

echo "==> Creating catalog bundle (tag=$COLLECTION_TAG, file=$BUNDLE)"
nkp create catalog-bundle --collection-tag "$COLLECTION_TAG" --output-file "$BUNDLE"

echo "==> Pushing $BUNDLE to $REGISTRY"
nkp push bundle --bundle "$BUNDLE" --to-registry "$REGISTRY"
