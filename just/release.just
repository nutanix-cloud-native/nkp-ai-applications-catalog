BUNDLE_NAME := "nkp-ai-applications-catalog"
DEFAULT_REGISTRY := "oci://ghcr.io/nutanix-cloud-native"

# Push the catalog bundle to the OCI registry (creates bundle first if needed)
# Usage: just push-bundle [tag] [registry] [skip] [chart-registry]
# Note: fallback to repo-<tag>.tar for older bundles created before fix
push-bundle tag=DEFAULT_TAG registry=DEFAULT_REGISTRY skip="" chart-registry=(env_var_or_default('CHART_REGISTRY', '')): (create-bundle tag skip chart-registry)
  env NKP_CLI="{{ NKP_CLI }}" ./scripts/push-bundle.sh "{{ BUNDLE_NAME }}" "{{ tag }}" "{{ registry }}"

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

# Release oci artifacts for catalog applications
[no-exit-message]
publish-artifacts release-spec registry: nkp-cli
  {{ NKP_CLI }} experimental catalog release --release-spec {{ release-spec }} --repo-dir "{{ REPO_ROOT }}" --push-to-registry {{ registry}}
