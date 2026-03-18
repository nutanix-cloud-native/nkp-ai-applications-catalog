BUNDLE_NAME := "nkp-ai-applications-catalog"
DEFAULT_REGISTRY := "oci://ghcr.io/nutanix-cloud-native/nkp-ai-applications-catalog"
DEFAULT_TAG := "v0.1.0"
# Base OCI registry for Helm charts in helmreleases. Override for testing:
#   CHART_REGISTRY=oci://ghcr.io/deepak-muley/charts just create-bundle
CHART_REGISTRY_BASE := "oci://ghcr.io/nutanix-cloud-native/charts"

# Create the catalog bundle (removes existing bundle file first)
# Usage: just create-bundle [tag] [skip] [chart-registry]
# skip: comma-separated app=version to exclude, e.g. "open-webui=12.0.1,kserve=0.16.0"
# chart-registry: override Helm chart OCI base (e.g. oci://ghcr.io/deepak-muley/charts) for testing
# Or set CHART_REGISTRY env var: CHART_REGISTRY=oci://ghcr.io/deepak-muley/charts just create-bundle
create-bundle tag=DEFAULT_TAG skip="" chart-registry=(env_var_or_default('CHART_REGISTRY', '')): nkp-cli
  env NKP_CLI="{{ NKP_CLI }}" ./scripts/create-bundle.sh "{{ REPO_ROOT }}" "{{ BUNDLE_NAME }}" "{{ CHART_REGISTRY_BASE }}" "{{ tag }}" "{{ skip }}" "{{ chart-registry }}"

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

# Create bundle and push to registry (for CI workflow_dispatch)
# Usage: just publish-artifacts <registry> <tag>
publish-artifacts registry tag:
  just validate
  just create-bundle {{ tag }}
  just push-bundle {{ tag }} {{ registry }}
