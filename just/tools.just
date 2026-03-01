# Repo root: directory containing the main justfile (invoked justfile is at repo root)
REPO_ROOT := justfile_directory()
LOCAL_DIR := REPO_ROOT + "/.local"
BIN_DIR := LOCAL_DIR + "/bin"

NKP_CLI_VERSION := "0.0.0-dev.0" # TODO: Update to latest stable

# Resolve nkp: use PATH first, then .local/bin, then download
NKP_CLI := if `which nkp 2>/dev/null || true` != "" {
  `which nkp`
} else {
  BIN_DIR + "/nkp"
}

# Ensure nkp CLI is available (uses PATH or downloads)
nkp-cli:
  ./scripts/ensure-nkp-cli.sh "{{ BIN_DIR }}" "{{ NKP_CLI_VERSION }}"

# Remove downloaded tools
clean:
  rm -rf "{{LOCAL_DIR}}"
