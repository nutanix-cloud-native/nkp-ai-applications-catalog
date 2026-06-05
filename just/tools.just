REPO_ROOT := justfile_directory()
LOCAL_DIR := REPO_ROOT + "/.local"
BIN_DIR := LOCAL_DIR + "/bin"

NKP_CLI_VERSION := "0.0.0-dev.0"
NKP_CLI := BIN_DIR + "/nkp"

# Ensure nkp CLI is available (uses PATH or downloads from downloads.d2iq.com)
[script]
nkp-cli:
  set -e
  if command -v nkp >/dev/null 2>&1; then
    echo "Using nkp from PATH: $(which nkp)"
    exit 0
  fi

  if [ -f "{{BIN_DIR}}/nkp" ]; then
    echo "Using nkp from {{BIN_DIR}}/nkp"
    exit 0
  fi

  mkdir -p "{{BIN_DIR}}"
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64)        arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "error: unsupported arch '$arch'"; exit 1 ;;
  esac

  asset="nkp_v{{NKP_CLI_VERSION}}_${os}_${arch}"
  url="https://downloads.d2iq.com/dkp/v{{NKP_CLI_VERSION}}/${asset}.tar.gz"

  echo "Fetching $url"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  if ! curl -L -sS -f "$url" | tar -xz -C "$tmpdir"; then
    echo "error: failed to download nkp from $url"
    exit 1
  fi

  found="$(find "$tmpdir" -name nkp -type f 2>/dev/null | head -1)"
  if [ -n "$found" ]; then
    mv "$found" "{{BIN_DIR}}/nkp"
  else
    echo "error: no nkp binary in tarball"
    exit 1
  fi
  chmod +x "{{BIN_DIR}}/nkp"
  echo "Installed {{BIN_DIR}}/nkp"

clean:
  rm -rf "{{LOCAL_DIR}}"
