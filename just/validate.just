# Validate each application artifact w.r.t the .bloodhound.yml config.
#
# NOTE: Validation pulls OCI charts from ghcr.io/nutanix-cloud-native/charts and requires authentication.
#       Login first: docker login ghcr.io  OR  helm registry login ghcr.io
validate: nkp-cli
  "{{ NKP_CLI }}" validate catalog-repository -v=3 --repo-dir="{{ REPO_ROOT }}"
