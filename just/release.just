BUNDLE_NAME := "nkp-ai-applications-catalog"
DEFAULT_REGISTRY := "oci://ghcr.io/nutanix-cloud-native/nkp-ai-applications-catalog"
DEFAULT_TAG := "v0.1.0"

# Create the catalog bundle (removes existing bundle file first)
create-bundle tag=DEFAULT_TAG: nkp-cli
  rm -f "./{{ BUNDLE_NAME }}-{{ tag }}.tar"
  "{{ NKP_CLI }}" create catalog-bundle --collection-tag "{{ tag }}"

# Push the catalog bundle to the OCI registry (creates bundle first if needed)
push-bundle tag=DEFAULT_TAG registry=DEFAULT_REGISTRY: (create-bundle tag)
  "{{ NKP_CLI }}" push bundle \
    --bundle "./{{ BUNDLE_NAME }}-{{ tag }}.tar" \
    --to-registry "{{ registry }}"

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
  just create-bundle {{ tag }}
  just push-bundle {{ tag }} {{ registry }}
