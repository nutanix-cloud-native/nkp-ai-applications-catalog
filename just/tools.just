REPO_ROOT := justfile_directory()
LOCAL_DIR := REPO_ROOT + "/.local"
BIN_DIR := LOCAL_DIR + "/bin"

NKP_CLI_VERSION := "0.0.0-dev.0"
NKP_CLI := BIN_DIR + "/nkp"
NKP_CHECKSUMS_URL := "https://downloads.d2iq.com/dkp/v" + NKP_CLI_VERSION + "/checksums.txt"
NKP_CHECKSUMS_LOCAL := BIN_DIR + "/checksums.txt"

# Ensure nkp CLI is available
[script]
nkp-cli:
  set -eo pipefail

  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  asset="nkp_v{{NKP_CLI_VERSION}}_${os}_amd64.tar.gz"

  if [ -f "{{NKP_CLI}}" ] && [ -f "{{NKP_CHECKSUMS_LOCAL}}" ]; then
    tmpfile="$(mktemp)"
    if curl -L -sS -f -o "$tmpfile" "{{NKP_CHECKSUMS_URL}}" 2>/dev/null; then
      if diff -u "{{NKP_CHECKSUMS_LOCAL}}" "$tmpfile" >/dev/null 2>&1; then
        rm -f "$tmpfile"
        echo "Using nkp from {{NKP_CLI}}"
        exit 0
      fi
      echo "Checksums changed, re-downloading..."
      diff -u "{{NKP_CHECKSUMS_LOCAL}}" "$tmpfile" || true
      rm -f "$tmpfile"
    else
      rm -f "$tmpfile"
      echo "Using nkp from {{NKP_CLI}}"
      exit 0
    fi
  fi

  mkdir -p "{{BIN_DIR}}"
  url="https://downloads.d2iq.com/dkp/v{{NKP_CLI_VERSION}}/${asset}"
  echo "Fetching $url"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  curl -LSsf "$url" | tar -xz -C "$tmpdir"
  mv "$tmpdir/nkp" "{{NKP_CLI}}"
  chmod +x "{{NKP_CLI}}"
  curl -L -sS -f "{{NKP_CHECKSUMS_URL}}" -o "{{NKP_CHECKSUMS_LOCAL}}" 2>/dev/null || true
  echo "Installed {{NKP_CLI}}"

clean:
  rm -rf "{{LOCAL_DIR}}"
