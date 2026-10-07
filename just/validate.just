# Guard catalog KFP tutorial samples against PyPI / python:3.9 regressions (NCN-118204).
verify-kfp-airgap-tutorials:
  bash "{{ REPO_ROOT }}/scripts/verify/kfp-airgap-tutorials.sh"

# Validate each application artifact w.r.t the .bloodhound.yml config.
#
# NOTE: Validation pulls OCI charts from ghcr.io/nutanix-cloud-native/charts and requires authentication.
#       Login first: docker login ghcr.io  OR  helm registry login ghcr.io
validate: bake-check nkp-cli verify-kfp-airgap-tutorials
  "{{ NKP_CLI }}" validate catalog-repository -v=3 --repo-dir="{{ REPO_ROOT }}" --artifacts-output {{ REPO_ROOT }}/artifacts.yaml
  cat {{ REPO_ROOT }}/artifacts.yaml
  git diff --exit-code HEAD || (printf "Error: $(FULL_BUNDLE_FILE) is out of date. Run 'make generate-artifacts-yaml' and commit.\n\n" && exit 1);
