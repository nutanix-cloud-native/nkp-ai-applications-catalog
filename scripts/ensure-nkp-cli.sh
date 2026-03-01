#!/bin/sh
# Ensure nkp CLI is available (uses PATH or downloads).
#
# Usage: ./scripts/ensure-nkp-cli.sh <bin-dir> [nkp-version]

set -e

BIN_DIR="${1:?Usage: $0 <bin-dir> [nkp-version]}"
NKP_CLI_VERSION="${2:-0.0.0-dev.0}"

# Already on PATH?
if command -v nkp >/dev/null 2>&1; then
  echo "Using nkp from PATH: $(which nkp)"
  exit 0
fi

# Already downloaded?
if [ -f "$BIN_DIR/nkp" ]; then
  echo "Using nkp from $BIN_DIR/nkp"
  exit 0
fi

# Download — support linux and darwin (x86_64/amd64 and arm64/aarch64)
mkdir -p "$BIN_DIR"
raw_os="$(uname -s)"
os=""
case "$raw_os" in
  Linux)  os="linux" ;;
  Darwin) os="darwin" ;;
  *)
    echo "error: unsupported OS '$raw_os'. Only Linux and macOS (darwin) are supported."
    echo "Install nkp on PATH (e.g. build from nkp-catalog-cli) and re-run."
    exit 1
    ;;
esac

raw_arch="$(uname -m)"
arch=""
case "$raw_arch" in
  x86_64)  arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *)
    echo "error: unsupported arch '$raw_arch'. Only x86_64, amd64, aarch64, arm64 are supported."
    exit 1
    ;;
esac

asset="nkp_v${NKP_CLI_VERSION}_${os}_${arch}"
url="https://downloads.d2iq.com/dkp/v${NKP_CLI_VERSION}/${asset}.tar.gz"

# arm64 often 403 on both linux and darwin; try amd64 as fallback (Rosetta on Mac, emulation on Linux)
if [ "$arch" = "arm64" ]; then
  if ! curl -sS -f -o /dev/null --head "$url" 2>/dev/null; then
    echo "${os}/arm64 not available, trying ${os}/amd64"
    asset="nkp_v${NKP_CLI_VERSION}_${os}_amd64"
    url="https://downloads.d2iq.com/dkp/v${NKP_CLI_VERSION}/${asset}.tar.gz"
  fi
fi

echo "Fetching $url"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
if ! curl -L -sS -f "$url" | tar -xz -C "$tmpdir"; then
  echo "error: failed to download or extract nkp from $url"
  echo "Install nkp on PATH (e.g. build from nkp-catalog-cli) and re-run."
  exit 1
fi

if [ -f "$tmpdir/nkp" ]; then
  mv "$tmpdir/nkp" "$BIN_DIR/nkp"
else
  found="$(find "$tmpdir" -name nkp -type f 2>/dev/null | head -1)"
  if [ -n "$found" ]; then
    mv "$found" "$BIN_DIR/nkp"
  else
    echo "error: no nkp binary in tarball"
    exit 1
  fi
fi
chmod +x "$BIN_DIR/nkp"
echo "Installed $BIN_DIR/nkp"
