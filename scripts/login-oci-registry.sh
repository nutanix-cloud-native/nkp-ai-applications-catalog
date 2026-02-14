#!/bin/sh
# Login to GHCR OCI registry.
# Reads GHCR_USERNAME and GHCR_PASSWORD from .env.local.
# Usage:
#   ./scripts/login-oci-registry.sh          # run directly (docker login)
#   source ./scripts/login-oci-registry.sh   # export vars into current shell

set -a
# shellcheck source=/dev/null
. "$(dirname "$0")/../.env.local"
set +a
export GHCR_USERNAME GHCR_PASSWORD

case "$0" in *login-oci-registry.sh)
  echo "Logging into ghcr.io..."
  docker login ghcr.io -u "$GHCR_USERNAME" -p "$GHCR_PASSWORD"
  echo "Done. To export GHCR creds into this shell, run: source $0"
  ;;
esac
