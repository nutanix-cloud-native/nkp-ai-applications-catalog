REPO_ROOT := justfile_directory()
LOCAL_DIR := REPO_ROOT + "/.local"
BIN_DIR := LOCAL_DIR + "/bin"

NKP_CLI_VERSION := "v0.0.0-dev.0"
NKP_CLI := BIN_DIR + "/nkp"

# Download nkp CLI from mesosphere/dkp-cli GitHub releases.
# Set GH_TOKEN env var for authentication (e.g. GITHUB_TOKEN in CI).
[script]
nkp-cli:
  if [ ! -f "{{NKP_CLI}}" ]; then
    mkdir -p "{{BIN_DIR}}"
    echo "Downloading nkp CLI {{NKP_CLI_VERSION}} to {{NKP_CLI}}"

    artifact_name="nkp_{{NKP_CLI_VERSION}}_linux_amd64.tar.gz"
    asset_url=$(curl -fsSL \
      -H "Authorization: token ${GH_TOKEN:-}" \
      "https://api.github.com/repos/mesosphere/dkp-cli/releases/tags/{{NKP_CLI_VERSION}}" \
      | jq -r ".assets[] | select(.name==\"${artifact_name}\") | .url")

    if [ -z "$asset_url" ] || [ "$asset_url" = "null" ]; then
      echo "Error: Could not find asset '${artifact_name}' in mesosphere/dkp-cli release {{NKP_CLI_VERSION}}"
      exit 1
    fi

    curl -fsSL \
      -H "Authorization: token ${GH_TOKEN:-}" \
      -H "Accept: application/octet-stream" \
      "${asset_url}" | tar xz -O nkp > "{{NKP_CLI}}"
    chmod +x "{{NKP_CLI}}"
  fi

clean:
  rm -rf "{{LOCAL_DIR}}"
