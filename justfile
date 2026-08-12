# NKP AI Applications Catalog — task runner
# Install just: https://github.com/casey/just
#
# Run `just` to list all recipes, or `just <recipe>` to run one.

set unstable

import 'just/artifacts.just'
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
