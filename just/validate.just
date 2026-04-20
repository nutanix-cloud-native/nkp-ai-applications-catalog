# Validate each application artifact w.r.t the .bloodhound.yml config.
# When CHART_REGISTRY is set, replaces chart URLs in a temp copy before validating (for testing).
# 
# NOTE: Validation pulls OCI charts from ghcr.io/nutanix-cloud-native/charts and requires authentication.
#       Login first: docker login ghcr.io  OR  helm registry login ghcr.io
validate: nkp-cli
  env NKP_CLI="{{ NKP_CLI }}" REPO_ROOT="{{ REPO_ROOT }}" CHART_REGISTRY_BASE="oci://ghcr.io/nutanix-cloud-native/charts" \
    ./scripts/validate-catalog.sh
