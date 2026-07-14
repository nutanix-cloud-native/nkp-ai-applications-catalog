# NKP AI Applications Catalog — task runner
# Install just: https://github.com/casey/just
#
# Run `just` to list all recipes, or `just <recipe>` to run one.

set unstable

import 'just/tools.just'
import 'just/validate.just'
import 'just/release.just'
import 'just/licenses.just'
import 'just/test.just'

# Default: list available recipes
default:
    @just --list

# ---------- Scaffold ----------

# Generate the application scaffold for a new app
# Usage: just generate-app <appname> <version>
generate-app appname version: nkp-cli
  "{{ NKP_CLI }}" generate catalog-repository --apps={{ appname }}={{ version }}

# ---------- Checks ----------

# Run pre-commit hooks and gitlint
# SKIP=git-dirty: allow running with uncommitted changes (validation run, not commit)
pre-commit:
    env VIRTUALENV_PIP=24.0 pre-commit install-hooks
    env SKIP=git-dirty pre-commit run -a --show-diff-on-failure
    git fetch origin main
    pre-commit run --hook-stage manual gitlint-ci

# Quick check: pre-commit only (no nkp CLI needed)
check: pre-commit

# Full check: pre-commit + catalog validation (ready to push)
check-all: pre-commit validate

# ---------- OCI registry ----------

# Login to GHCR (reads .env.local)
login:
    ./scripts/login-oci-registry.sh

# ---------- Helm → OCI ----------

# Base OCI registry for Helm chart pushes. Override for testing:
#   OCI_REGISTRY=oci://my-registry.com/charts just push-ollama
OCI_REGISTRY := env_var_or_default('OCI_REGISTRY', 'oci://ghcr.io/nutanix-cloud-native/charts')

# Mirror a chart from a Helm repository to our OCI registry
# Usage: just mirror-chart-from-repo <repo-url> <chart> <version> [oci-registry]
mirror-chart-from-repo repo-url chart version oci-registry=OCI_REGISTRY:
    ./scripts/push-helm-to-oci.sh {{repo-url}} {{chart}} {{version}} {{oci-registry}}

# Package a bake-generated chart (charts/<app>, produced by `just bake <app>`)
# and push it to our OCI registry. Login first with `just login`.
# Usage: just push-baked-chart kubeflow-central-dashboard [oci-registry]
push-baked-chart app oci-registry=OCI_REGISTRY:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -f "charts/{{ app }}/Chart.yaml" ] || { echo "No chart at charts/{{ app }}; run 'just bake {{ app }}' first" >&2; exit 1; }
    workdir=$(mktemp -d)
    trap 'rm -rf "$workdir"' EXIT
    echo "==> Packaging charts/{{ app }}"
    helm package "charts/{{ app }}" -d "$workdir"
    echo "==> Pushing to {{ oci-registry }}"
    helm push "$workdir"/*.tgz {{ oci-registry }}

# Push the generated kubeflow-central-dashboard chart to OCI.
push-kubeflow-central-dashboard: (push-baked-chart "kubeflow-central-dashboard")

# Mirror a chart from an upstream OCI registry to our OCI registry
# Usage: just mirror-chart-from-oci oci://upstream-registry/chart <version> [oci-registry]
mirror-chart-from-oci upstream-oci-url upstream-version oci-registry=OCI_REGISTRY:
    #!/usr/bin/env bash
    set -euo pipefail
    workdir=$(mktemp -d)
    trap 'rm -rf "$workdir"' EXIT
    echo "==> Pulling {{upstream-oci-url}} version {{upstream-version}}"
    helm pull {{upstream-oci-url}} --version {{upstream-version}} -d "$workdir"
    echo "==> Pushing to {{oci-registry}}"
    helm push "$workdir"/*.tgz {{oci-registry}}

# ---------- Render & bake (air-gappable manifests) ----------

# Re-render and bake an app's self-contained manifest set into its helmrelease/
# dir. Reads scripts/bake-apps.yaml (repo + per-version ref/overlays/airgapImages).
# Omit the version to (re-)bake every configured version of the app.
# Usage: just bake kubeflow-pipelines [2.15.0]
bake app version="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{ version }}" ]; then
      ./scripts/build-baked-manifests.sh --app "{{ app }}" --version "{{ version }}"
    else
      ./scripts/build-baked-manifests.sh --app "{{ app }}"
    fi

# Re-bake every configured app+version and fail if a committed artifact drifted
# from a fresh render (a flat manifest under applications/, a generated chart under
# charts/, or an airgapImages lockfile that drifted from the upstream ref).
# Pin kustomize (devbox) so it's reproducible.
bake-check:
    #!/usr/bin/env bash
    set -euo pipefail
    for app in $(yq -r '.apps | keys | .[]' scripts/bake-apps.yaml); do
      ./scripts/build-baked-manifests.sh --app "$app"
    done
    if ! git diff --exit-code -- applications/ charts/; then
      echo "::error::Baked artifacts are stale. Run 'just bake <app> [version]' and commit the result." >&2
      exit 1
    fi
