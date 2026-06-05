REPO_ROOT := justfile_directory()
LOCAL_DIR := REPO_ROOT + "/.local"
BIN_DIR := LOCAL_DIR + "/bin"

NKP_CLI_VERSION := "v0.0.0-dev.0"
NKP_CLI := BIN_DIR + "/nkp"

# Download nkp CLI from mesosphere/dkp-cli GitHub releases
[script]
nkp-cli:
  if [ ! -f "{{NKP_CLI}}" ]; then
    mkdir -p "{{BIN_DIR}}"
    echo "Downloading nkp CLI {{NKP_CLI_VERSION}} to {{NKP_CLI}}"

    gh release download "{{NKP_CLI_VERSION}}" \
      -R mesosphere/dkp-cli \
      -p 'nkp*linux_amd64*' \
      --clobber -O - \
    | tar xz -C "{{BIN_DIR}}" --wildcards 'nkp' || {
      echo "Error: Failed to download or extract NKP CLI."
      exit 1
    }
  fi

clean:
  rm -rf "{{LOCAL_DIR}}"
