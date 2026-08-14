# Generate per-app licenses.yaml files under applications/<app>/<version>/.
#
# Usage:
#   just generate-licenses
#   just generate-licenses
#   just generate-licenses kagent=0.9.12 ollama=1.72.0
#   just generate-licenses amd*
#
# Notes:
# - `apps` accepts the same format as `nkp validate catalog-repository --apps`.
# - Non app=version tokens are treated as app-name globs (matched in applications/).
# - When empty, all applications are processed.
[script]
generate-licenses *apps: nkp-cli
  repo_root="{{ REPO_ROOT }}"
  nkp_cli="{{ NKP_CLI }}"
  filters=""
  set -- {{apps}}

  if [ "$#" -eq 0 ]; then
    "$nkp_cli" validate catalog-repository -v=3 --repo-dir="$repo_root" --licenses-per-app --artifacts-output="artifacts.yaml"
    exit 0
  fi

  for token in "$@"; do
    if [[ "$token" == *"="* ]]; then
      filters="${filters:+$filters,}$token"
      continue
    fi

    matched=0
    for app_dir in "$repo_root"/applications/$token; do
      [ -d "$app_dir" ] || continue
      app_name="$(basename "$app_dir")"
      for ver_dir in "$app_dir"/*; do
        [ -d "$ver_dir" ] || continue
        filters="${filters:+$filters,}$app_name=$(basename "$ver_dir")"
        matched=1
      done
    done
    if [ "$matched" -eq 0 ]; then
      echo "warning: no applications matched pattern: $token" >&2
    fi
  done

  if [ -z "$filters" ]; then
    echo "error: no apps resolved from input: $*" >&2
    exit 1
  fi

  "$nkp_cli" validate catalog-repository -v=3 --repo-dir="$repo_root" --licenses-per-app --artifacts-output="artifacts.yaml" --apps="$filters"
