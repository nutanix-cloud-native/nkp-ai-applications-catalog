#!/bin/sh
# Login to GHCR OCI registry.
# Credentials can be provided via:
#   1. .env.local file (GHCR_USERNAME, GHCR_PASSWORD)
#   2. Environment variables (GITHUB_USERNAME, GITHUB_TOKEN)
#   3. Environment variables (GHCR_USERNAME, GHCR_PASSWORD)
#
# Usage:
#   ./scripts/login-oci-registry.sh          # run directly (docker login)
#   source ./scripts/login-oci-registry.sh   # export vars into current shell

# Try to load .env.local if it exists
if [ -f "$(dirname "$0")/../.env.local" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$(dirname "$0")/../.env.local"
  set +a
fi

# Fallback to standard GitHub env vars if GHCR_* not set
: "${GHCR_USERNAME:=$GITHUB_USERNAME}"
: "${GHCR_PASSWORD:=$GITHUB_TOKEN}"

export GHCR_USERNAME GHCR_PASSWORD

case "$0" in *login-oci-registry.sh)
  if [ -z "$GHCR_USERNAME" ] || [ -z "$GHCR_PASSWORD" ]; then
    echo "ERROR: GitHub credentials not found."
    echo "Please set one of:"
    echo "  - GITHUB_USERNAME and GITHUB_TOKEN environment variables"
    echo "  - GHCR_USERNAME and GHCR_PASSWORD in .env.local"
    exit 1
  fi
  echo "Logging into ghcr.io as $GHCR_USERNAME..."
  docker login ghcr.io -u "$GHCR_USERNAME" -p "$GHCR_PASSWORD"
  echo "Done. To export GHCR creds into this shell, run: source $0"
  ;;
esac
