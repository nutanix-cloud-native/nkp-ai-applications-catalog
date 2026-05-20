# Testing

This document covers the end-to-end (E2E) test framework for validating AI
applications catalog entries.

## Prerequisites

All commands assume you are inside a [devbox](https://www.jetify.com/devbox)
shell. Start one with:

```sh
devbox shell
```

Devbox provides Go, just, jq, and other tools at consistent versions. The shell
init hook adds `.local/bin` to `PATH`, which is where the `nkp` CLI is
downloaded to.

## Running Tests Locally

### Single application

```sh
just e2e-test <app> <version>
```

For example:

```sh
just e2e-test ollama 1.39.0
```

By default this creates an ephemeral [Kind](https://kind.sigs.k8s.io/) cluster,
installs Flux, deploys the application, and validates the HelmRelease reaches a
`Ready` state. The cluster is torn down after the test completes.

### All applications

```sh
just e2e-test-all
```

This iterates over every `applications/<app>/<version>/` directory and runs
`just e2e-test` for each combination.

### Using an existing cluster

To skip Kind cluster creation and run against a cluster you already have:

```sh
E2E_KUBECONFIG=~/.kube/config just e2e-test ollama 1.39.0
```

When `E2E_KUBECONFIG` is set, the test suite connects to the cluster at that
kubeconfig path instead of provisioning a new Kind cluster. Cluster teardown is
also skipped.

### Skipping cluster teardown

To keep the Kind cluster around after a test run (useful for debugging):

```sh
SKIP_CLUSTER_TEARDOWN=1 just e2e-test ollama 1.39.0
```

### Running specific test labels

The test suites use [Ginkgo v2](https://onsi.github.io/ginkgo/) labels. Each
application has a label matching its directory name, and each test type has a
label (`install`, `upgrade`). You can filter further by editing the
`--ginkgo.label-filter` flag, for example to run only install tests:

```sh
cd apptests && go test ./suites/ -v -count=1 \
  --ginkgo.label-filter="ollama && install" \
  -app-version=1.39.0
```

### Docker host

If you use Colima or another non-default Docker runtime, set `DOCKER_HOST` so
Kind can find the Docker socket:

```sh
export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock
```

## CI Workflow

The E2E tests run automatically via the `.github/workflows/e2e.yaml` workflow.

### Triggers

| Event | Behavior |
|---|---|
| PR opened/synchronized | Detects changed apps via `git diff` and tests only affected app/version pairs. If only `apptests/` changed (no app diffs), no tests run. |
| PR with `run-e2e-all` label | Tests all app/version combinations regardless of diff. |
| Push to `main` | Tests all app/version combinations (full matrix). |

The workflow only triggers when files under `applications/` or `apptests/` are
modified.

### How matrix detection works

The `detect-apps` job compares the PR diff against `applications/` to extract
`<app>/<version>` pairs. Each pair becomes a matrix entry. If no application
files changed (e.g. only `apptests/` was modified), the matrix is empty and the
e2e job is skipped. On `main` or when `run-e2e-all` is set, every
`applications/<app>/<version>/` directory is included.

### Diagnostic bundles

When a test fails in CI, the workflow automatically:

1. Runs `nkp diagnose` to collect a diagnostic bundle from the cluster.
2. Uploads the bundle as a GitHub Actions artifact named
   `e2e-<app>-<version>`.

You can download these from the workflow run's **Artifacts** section.

## Test Structure

Tests live in `apptests/suites/` and use the generic `catalog.App` scenario
from `apptests/catalog/app.go`.

Each test file follows this pattern:

- **Install block** (`Label("install")`) -- creates a cluster, installs the
  app, and asserts the HelmRelease becomes Ready.
- **Upgrade block** (`Label("upgrade")`) -- checks if a previous version
  exists. If not, the entire block is skipped without creating a cluster. If
  yes, installs the previous version, upgrades to the current version, and
  asserts success.

Each block manages its own cluster lifecycle independently, so skipped upgrade
tests don't waste time provisioning clusters.

## Adding a New Application Test

1. Create the application directory under `applications/<name>/<version>/`.
2. Add a test file `apptests/suites/<name>_test.go` following the pattern in
   existing test files.
3. Use `catalog.NewAppScenario("<name>", *appVersion)` to get the generic
   scenario -- no custom scenario code needed unless the app requires
   pre-install setup (secrets, config patches, etc.).
4. Label the outer `Describe` with `Label("<name>")` matching the directory
   name so the CI matrix and `just e2e-test` can filter to it.
