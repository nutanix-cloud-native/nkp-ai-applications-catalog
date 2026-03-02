#!/bin/sh
# Push the catalog bundle to an OCI registry.
#
# Usage:
#   ./scripts/push-bundle.sh <bundle-name> <tag> <registry>
#
# Note: fallback to repo-<tag>.tar for older bundles created before fix.

set -e

BUNDLE_NAME="${1:?Usage: $0 <bundle-name> <tag> <registry>}"
TAG="${2:?Missing tag}"
REGISTRY="${3:?Missing registry}"
NKP_CLI="${NKP_CLI:?NKP_CLI must be set}"

bundle1="./${BUNDLE_NAME}-${TAG}.tar"
bundle2="./repo-${TAG}.tar"

if [ -f "$bundle1" ]; then
  bundle="$bundle1"
elif [ -f "$bundle2" ]; then
  bundle="$bundle2"
else
  echo "ERROR: Bundle not found. Tried $bundle1 and $bundle2"
  exit 1
fi

"$NKP_CLI" push bundle --bundle "$bundle" --to-registry "$REGISTRY"
