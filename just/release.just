BUNDLE_NAME := "nkp-ai-applications-catalog"
DEFAULT_REGISTRY := "oci://ghcr.io/nutanix-cloud-native"

# Deploy the catalog collection to an NKP cluster
add-to-cluster workspace tag registry=(DEFAULT_REGISTRY + "/" + BUNDLE_NAME + "/collection"): nkp-cli
  "{{ NKP_CLI }}" create catalog-collection \
    --url "{{ registry }}" \
    --tag "{{ tag }}" \
    --dry-run \
    --workspace "{{ workspace }}"

# Release oci artifacts for catalog applications
[no-exit-message]
publish-artifacts release-spec registry: nkp-cli
  {{ NKP_CLI }} experimental catalog release --release-spec {{ release-spec }} --repo-dir "{{ REPO_ROOT }}" --push-to-registry {{ registry}}


# Create an airgapped bundle for a single application
# Example: just create-application-airgapped-bundle amd-gpu-operator 1.5.0
[script]
create-application-airgapped-bundle application-name application-version output-file="": nkp-cli
  tmpfile=$(mktemp)
  trap "rm -f $tmpfile" EXIT
  output_file="{{output-file}}"

  if [ -z "$output_file" ]; then
    output_file="{{application-name}}-{{application-version}}-airgapped.tar"
  fi

  cp "{{ REPO_ROOT }}/.release/airgapped.yaml.tmpl" "$tmpfile"

  OUTPUT_FILE="$output_file" APP_NAME="{{application-name}}" APP_VERSION="{{application-version}}" yq -i \
    '.releases[0].fileName = strenv(OUTPUT_FILE) |
     .releases[0].applications = [{"name": strenv(APP_NAME), "version": strenv(APP_VERSION)}]' \
    "$tmpfile"

  echo "Building application bundle for {{application-name}} {{application-version}}... (output file: $output_file)"
  cat "$tmpfile"
  "{{ NKP_CLI }}" experimental catalog release --release-spec "$tmpfile" --repo-dir "{{ REPO_ROOT }}"

# Create an airgapped bundle for a collection of applications.
# Usage: just create-collection-airgapped-bundle <collection-tag> [output-file] [release-spec]
[script]
create-collection-airgapped-bundle collection-tag output-file="" release-spec=".release/dev.yaml": nkp-cli
  output_file="{{output-file}}"
  tag_name="{{collection-tag}}"

  if [ -z "$output_file" ]; then
    output_file="nkp-ai-applications-catalog-{{collection-tag}}-airgapped.tar"
  fi

  if [ -z "$(yq '.releases[] | select(.tagName == "'"$tag_name"'")' {{release-spec}})" ]; then
    echo "Error: Tag '$tag_name' not found in {{release-spec}}"
    exit 1
  fi

  tmpfile=$(mktemp)
  trap "rm -f $tmpfile" EXIT
  cp "{{ REPO_ROOT }}/.release/airgapped.yaml.tmpl" "$tmpfile"

  OUTPUT_FILE="$output_file" TAG_NAME="$tag_name" yq -i \
    '.releases[0].tagName = strenv(TAG_NAME) |
     .releases[0].fileName = strenv(OUTPUT_FILE) |
     .releases[0].applications = (load("{{release-spec}}") | .releases[] | select(.tagName == strenv(TAG_NAME)) | .applications)' \
    "$tmpfile"

  echo "Building collection airgapped bundle for $tag_name... (output file: $output_file)"
  cat "$tmpfile"
  "{{ NKP_CLI }}" experimental catalog release --release-spec "$tmpfile" --repo-dir "{{ REPO_ROOT }}"

# Build and push airgapped bundles to S3
[script]
push-airgapped-bundles release-spec s3-dest dry-run="false": nkp-cli
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT

  dryrun_flag=""
  if [ "{{ dry-run }}" = "true" ]; then
    dryrun_flag="--dryrun"
  fi

  for tag in $(yq '.releases[] | .tagName' {{ release-spec }}); do
    bundle="${tmpdir}/${tag}-airgapped.tar"
    echo "Building airgapped bundle for $tag..."
    just create-collection-airgapped-bundle "$tag" "$bundle" {{ release-spec }}

    dest="{{ s3-dest }}/nkp-ai-applications-catalog-airgapped-${tag}.tar"
    echo "Uploading $bundle -> $dest"
    aws s3 cp $dryrun_flag "$bundle" "$dest"
  done
