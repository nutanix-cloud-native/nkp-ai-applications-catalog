BUNDLE_NAME := "nkp-ai-applications-catalog"
DEFAULT_REGISTRY := "oci://ghcr.io/nutanix-cloud-native/nkp-ai-applications-catalog"
DEFAULT_TAG := "v0.1.0"
# Base OCI registry for Helm charts in helmreleases. Override for testing:
#   CHART_REGISTRY=oci://ghcr.io/deepak-muley/charts just create-bundle
CHART_REGISTRY_BASE := "oci://ghcr.io/nutanix-cloud-native/charts"

# Create the catalog bundle (removes existing bundle file first)
# Usage: just create-bundle [tag] [skip] [chart-registry]
# skip: comma-separated app=version to exclude, e.g. "openwebui=12.0.1,kserve=0.16.0"
# chart-registry: override Helm chart OCI base (e.g. oci://ghcr.io/deepak-muley/charts) for testing
# Or set CHART_REGISTRY env var: CHART_REGISTRY=oci://ghcr.io/deepak-muley/charts just create-bundle
[script]
create-bundle tag=DEFAULT_TAG skip="" chart-registry=(env_var_or_default('CHART_REGISTRY', '')): nkp-cli
  rm -f "./{{ BUNDLE_NAME }}-{{ tag }}.tar"
  use_custom_registry=""
  if [ -n "{{chart-registry}}" ]; then
    use_custom_registry=1
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT
    repodir="$tmpdir/{{ BUNDLE_NAME }}"
    rsync -a --exclude='.git' --exclude='.cursor' "{{ REPO_ROOT }}/" "$repodir/" 2>/dev/null || cp -a "{{ REPO_ROOT }}" "$repodir"
    find "$repodir/applications" -name "*.yaml" -type f -exec sed -i.bak "s|{{ CHART_REGISTRY_BASE }}|{{chart-registry}}|g" {} \;
    find "$repodir/applications" -name "*.bak" -delete
  else
    repodir="{{ REPO_ROOT }}"
  fi
  if [ -z "{{skip}}" ]; then
    "{{ NKP_CLI }}" create catalog-bundle --repo-dir "$repodir" --collection-tag "{{ tag }}"
  else
    apps_dir="{{ REPO_ROOT }}/applications"
    all_apps=""
    for app_dir in "$apps_dir"/*/; do
      app="$(basename "$app_dir")"
      for ver_dir in "$app_dir"*/; do
        [ -d "$ver_dir" ] || continue
        ver="$(basename "$ver_dir")"
        all_apps="${all_apps}${app}=${ver},"
      done
    done
    all_apps="${all_apps%,}"
    skip_list="$(echo "{{skip}}" | tr ',' '\n' | tr -d ' ')"
    include_apps=""
    for item in $(echo "$all_apps" | tr ',' '\n'); do
      skip=0
      for s in $skip_list; do
        [ "$item" = "$s" ] && skip=1 && break
      done
      [ $skip -eq 0 ] && include_apps="${include_apps}${item},"
    done
    include_apps="${include_apps%,}"
    [ -z "$include_apps" ] && echo "No apps to bundle after skipping" && exit 1
    "{{ NKP_CLI }}" create catalog-bundle --repo-dir "$repodir" --collection-tag "{{ tag }}" --apps="$include_apps"
  fi
  if [ -n "$use_custom_registry" ]; then
    bundle_in_repo="$repodir/{{ BUNDLE_NAME }}-{{ tag }}.tar"
    if [ -f "$bundle_in_repo" ]; then
      mv "$bundle_in_repo" "{{ REPO_ROOT }}/"
    fi
  fi

# Push the catalog bundle to the OCI registry (creates bundle first if needed)
# Usage: just push-bundle [tag] [registry] [skip] [chart-registry]
# Note: fallback to repo-<tag>.tar for older bundles created before fix
[script]
push-bundle tag=DEFAULT_TAG registry=DEFAULT_REGISTRY skip="" chart-registry=(env_var_or_default('CHART_REGISTRY', '')): (create-bundle tag skip chart-registry)
  bundle1="./{{ BUNDLE_NAME }}-{{ tag }}.tar"
  bundle2="./repo-{{ tag }}.tar"
  if [ -f "$bundle1" ]; then
    bundle="$bundle1"
  elif [ -f "$bundle2" ]; then
    bundle="$bundle2"
  else
    echo "ERROR: Bundle not found. Tried $bundle1 and $bundle2"
    exit 1
  fi
  "{{ NKP_CLI }}" push bundle --bundle "$bundle" --to-registry "{{ registry }}"

# Deploy the catalog collection to an NKP cluster
add-to-cluster workspace="dm-dev-workspace" tag=DEFAULT_TAG registry=(DEFAULT_REGISTRY + "/" + BUNDLE_NAME + "/collection"): nkp-cli
  "{{ NKP_CLI }}" create catalog-collection \
    --url "{{ registry }}" \
    --tag "{{ tag }}" \
    --dry-run \
    --workspace "{{ workspace }}"

# Full pipeline: validate → bundle → push
release tag=DEFAULT_TAG registry=DEFAULT_REGISTRY:
  just validate
  just create-bundle {{ tag }}
  just push-bundle {{ tag }} {{ registry }}

# Create bundle and push to registry (for CI workflow_dispatch)
# Usage: just publish-artifacts <registry> <tag>
publish-artifacts registry tag:
  just validate
  just create-bundle {{ tag }}
  just push-bundle {{ tag }} {{ registry }}

