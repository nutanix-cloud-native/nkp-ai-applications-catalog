#!/bin/sh
# Demo script for NKP catalog sample apps (demo-connector, demo-rag, demo-full-rag).
#
# Usage:
#   ./scripts/demo-catalog.sh build     # Build and push images + charts
#   ./scripts/demo-catalog.sh bundle   # Validate and create catalog bundle
#   ./scripts/demo-catalog.sh deploy   # Deploy catalog to cluster (dry-run by default)
#   ./scripts/demo-catalog.sh all      # Run build + bundle
#
# Prerequisites:
#   - docker login ghcr.io
#   - helm registry login ghcr.io
#   - nkp-demo-connector, nkp-demo-rag, nkp-demo-full-rag repos at ../../deepak-muley/ (or set DEMO_*)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEMO_CONNECTOR="${DEMO_CONNECTOR:-$REPO_ROOT/../../deepak-muley/nkp-demo-connector}"
DEMO_RAG="${DEMO_RAG:-$REPO_ROOT/../../deepak-muley/nkp-demo-rag}"
DEMO_FULL_RAG="${DEMO_FULL_RAG:-$REPO_ROOT/../../deepak-muley/nkp-demo-full-rag}"
VERSION="${VERSION:-1.1.0}"
DEMO_FULL_RAG_VERSION="${DEMO_FULL_RAG_VERSION:-1.1.0}"

build() {
  echo "==> Building demo-connector..."
  (cd "$DEMO_CONNECTOR" && make release VERSION="$VERSION")
  echo "==> Building demo-rag..."
  (cd "$DEMO_RAG" && make release VERSION="$VERSION")
  echo "==> Building demo-full-rag..."
  (cd "$DEMO_FULL_RAG" && make release VERSION="$DEMO_FULL_RAG_VERSION")
  echo "==> Done. Images and charts pushed to ghcr.io/deepak-muley"
}

bundle() {
  echo "==> Validating catalog..."
  (cd "$REPO_ROOT" && just validate)
  echo "==> Creating and pushing bundle..."
  (cd "$REPO_ROOT" && just push-bundle v0.1.0 oci://ghcr.io/deepak-muley/nkp-ai-applications-catalog)
  echo "==> Done. Bundle pushed."
}

deploy() {
  WORKSPACE="${1:-dm-dev-workspace}"
  echo "==> Deploying catalog to workspace: $WORKSPACE"
  (cd "$REPO_ROOT" && just add-to-cluster "$WORKSPACE" v0.1.0 oci://ghcr.io/deepak-muley/nkp-ai-applications-catalog/nkp-ai-applications-catalog/collection)
  echo "==> Remove --dry-run from the command to actually deploy."
}

case "${1:-}" in
build) build ;;
bundle) bundle ;;
deploy) deploy "${2:-}" ;;
all) build && bundle ;;
*)
  echo "Usage: $0 {build|bundle|deploy|all} [workspace]"
  echo ""
  echo "  build   - Build and push demo-connector + demo-rag + demo-full-rag images and charts"
  echo "  bundle  - Validate catalog and push bundle to OCI"
  echo "  deploy  - Deploy catalog to cluster (dry-run)"
  echo "  all     - build + bundle"
  exit 1
  ;;
esac
