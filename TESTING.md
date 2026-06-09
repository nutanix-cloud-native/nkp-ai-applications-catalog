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
just e2e-test kagent 0.7.13
```

By default this creates an ephemeral [Kind](https://kind.sigs.k8s.io/) cluster,
installs Flux, deploys the application, and validates the HelmRelease reaches a
`Ready` state. The cluster is torn down after the test completes.

### Using an existing cluster

To skip Kind cluster creation and run against a cluster you already have:

```sh
E2E_KUBECONFIG=~/.kube/config just e2e-test kagent 0.7.13
```

When `E2E_KUBECONFIG` is set, the test suite connects to the cluster at that
kubeconfig path instead of provisioning a new Kind cluster. Cluster teardown is
also skipped.

### Skipping cluster teardown

To keep the Kind cluster around after a test run (useful for debugging):

```sh
SKIP_CLUSTER_TEARDOWN=1 just e2e-test kagent 0.7.13
```

### Running specific test labels

The test suites use [Ginkgo v2](https://onsi.github.io/ginkgo/) labels. Each
application has a label matching its directory name, and each test type has a
label (`install`, `upgrade`). You can filter with `--ginkgo.label-filter`:

```sh
cd apptests && go test ./suites/ -v -count=1 \
  --ginkgo.label-filter="kagent && install" \
  -app-version=0.7.13
```

### Docker host

If you use Colima or another non-default Docker runtime, set `DOCKER_HOST` so
Kind can find the Docker socket:

```sh
export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock
```

## CI Workflow

The E2E tests are **opt-in** per application. Tests only run for applications
explicitly registered in the `enabledApps` list in
`apptests/suites/suites_test.go`.

The workflow is defined in `.github/workflows/e2e.yaml`.

### Triggers

| Event | Behavior |
|---|---|
| PR with `e2e-<app>` label | Tests the named app (must be in `enabledApps`). |
| PR with `run-e2e-all` label | Tests all apps in `enabledApps`. |
| PR with no `e2e-*` labels | No tests run. |
| `workflow_dispatch` with app input | Tests the specified app. |
| `workflow_dispatch` without app input | Tests all apps in `enabledApps`. |
| Push to `main` (touching `apptests/`) | Tests all apps in `enabledApps`. |

### How matrix detection works

The `detect-apps` job reads the `enabledApps` slice from `suites_test.go` to
determine which applications have tests. It intersects this list with any
`e2e-<app>` PR labels to build the matrix. Each `app/version` pair becomes a
separate CI job. If no labels are present on a PR, the matrix is empty and the
e2e job is skipped.

### Diagnostic bundles

When a test fails in CI, the workflow automatically:

1. Runs `nkp diagnose` to collect a diagnostic bundle from the cluster.
2. Uploads the bundle as a GitHub Actions artifact named
   `e2e-<app>-<version>`.

You can download these from the workflow run's **Artifacts** section.

## Test Structure

Tests use the shared `catalog` package from
[kommander-applications/apptests/catalog](https://github.com/mesosphere/kommander-applications/tree/main/apptests/catalog).
This package provides:

- `InitSuite` / `RunSuite` -- Ginkgo suite bootstrap and global variables
- `SetupKindCluster` / `TeardownCluster` -- Kind cluster lifecycle with
  `E2E_KUBECONFIG` support
- `RegisterDefaultTests` -- template install + upgrade test blocks
- `NewAppScenario` -- generic `App` implementing the `AppScenario` interface

Each template test follows this pattern:

- **Install block** (`Label("install")`) -- creates a cluster, installs Flux,
  deploys the app, and asserts the HelmRelease becomes Ready.
- **Upgrade block** (`Label("upgrade")`) -- checks if a previous version
  exists. If not, the block is skipped. If yes, installs the previous version,
  upgrades, and asserts success.

Each block manages its own cluster lifecycle, so skipped upgrade tests don't
waste time provisioning clusters.

## Enabling Tests for an Application

Add the application name to the `enabledApps` slice in
`apptests/suites/suites_test.go`:

```go
var enabledApps = []string{
	"kagent",
	"your-new-app",
}
```

This registers the default install + upgrade template test for the app. No
other files are needed.

## Custom Test Files

If an application needs pre-install setup (secrets, ConfigMap patches, CRDs,
etc.), create a dedicated `apptests/suites/<app>_test.go` file instead:

1. Write a Ginkgo `Describe` block with `Label("<app>")` matching the
   directory name.
2. Use `catalog.SetupKindCluster()`, `catalog.Env`, `catalog.K8sClient`, and
   `catalog.NewAppScenario("<app>", *catalog.AppVersion)` from the shared
   package.
3. Do **not** add the app to `enabledApps` -- the custom test file registers
   its own Ginkgo blocks directly.
