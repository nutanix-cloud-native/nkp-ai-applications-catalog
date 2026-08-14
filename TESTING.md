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
installs Flux, deploys the application, and validates the app reconciler reaches
`Ready` (`HelmRelease` for Helm apps, or Flux `GitRepository` +
`Kustomization` for Flux-Kustomize apps). The cluster is torn down after the
test completes.

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

The `detect-apps` job reads the `enabledApps` **and** `customTestApps` slices
from `suites_test.go` to determine which applications have tests. It intersects
this union with any `e2e-<app>` PR labels to build the matrix. Each `app/version`
pair becomes a separate CI job. If no labels are present on a PR, the matrix is
empty and the e2e job is skipped.

> Apps with a dedicated `<app>_test.go` (see [Custom Test Files](#custom-test-files))
> must be listed in `customTestApps` so their `e2e-<app>` label is recognized by
> matrix detection.

### Diagnostic bundles

When a test fails in CI, the workflow automatically:

1. Runs `nkp diagnose` to collect a diagnostic bundle from the cluster.
2. Uploads the bundle as a GitHub Actions artifact named
   `e2e-<app>-<version>`.

You can download these from the workflow run's **Artifacts** section.

### Airgapped bundle artifacts

When an app's E2E test passes, the workflow also builds an **airgapped** catalog
bundle for the `app/version` under test by running
`just create-application-airgapped-bundle <app> <version>`. That recipe renders
`.release/airgapped.yaml.tmpl` (`includeApplicationImages: true`) for the single
app, so the tarball includes the container images and OCI artifacts needed to
deploy on a disconnected cluster — not just the manifests and image references.
The generated `<app>-<version>-airgapped.tar` is uploaded as a GitHub Actions
artifact named `airgapped-bundle-<app>-<version>`.

> **Only self-contained (HelmRelease) apps are bundled.** The matrix builder tags
> each entry with `airgapped: true` for `enabledApps` and `airgapped: false` for
> `customTestApps`, and the bundle steps run only when `matrix.airgapped` is true.
>
> The Flux-Kustomize apps deploy from a remote `GitRepository`
> (`github.com/kubeflow/manifests`) whose overlays reference parent paths such as
> `../../base`. Flux's kustomize-controller builds these fine (that's why E2E
> passes), but `nkp create catalog-bundle`'s Flux-Kustomization parser re-parses
> each overlay with a stricter load-restrictor anchored at the overlay `path`, so
> the parent reference trips `fs-security-constraint` and the bundle build fails.
> Skipping the bundle step for these apps sidesteps that parser limitation.
>
> This is a manifest-parsing limitation, **not** a missing-images problem: the
> container images for these apps are discoverable and mirrorable today via
> `scripts/mirror-kubeflow-images.sh` (see `scripts/kubeflow-kustomize-apps.yaml`;
> `kubeflow-pipelines` is excluded because it has remote Kustomize refs that fail
> even in Flux). Full airgap-in-the-bundle needs the upstream manifests vendored
> into the catalog (dropping the remote `GitRepository` and flattening overlays so
> the bundle parser accepts them); once vendored, flip the app's `airgapped` flag
> on and the bundle step covers it.

## Test Structure

Tests use the shared `catalog` package consumed by this repository. It provides:

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

Apps fall into two categories by how they reconcile. Add the app name to the
matching slice in `apptests/suites/suites_test.go` -- no other files are needed,
and each app gets a generic install (+ upgrade, where applicable) test.

- **HelmRelease apps** -> `enabledApps`. Success is the app's `HelmRelease`
  reaching `Ready`.
- **Flux-Kustomize apps** (deploy via `GitRepository` + `Kustomization`) ->
  `customTestApps`. Success is the Flux source and `Kustomization` reaching
  `Ready`.

```go
var enabledApps = []string{        // HelmRelease apps
	"kagent",
	"your-helm-app",
}

var customTestApps = []string{     // Flux-Kustomize apps
	"katib",
	"your-kustomize-app",
}
```

An `init()` guard panics if an app is listed in both. CI matrix detection reads
both slices, so listing the app is all that is required for its `e2e-<app>`
label to work.

## Platform dependencies

Apps declare the platform apps they need (Istio, cert-manager, ...) in
`requiredDependencies` in their `metadata.yaml`. Both the Helm and Kustomize
suites read that list and provision a lightweight stand-in for each entry before
install, so metadata is the single source of truth -- tests never hardcode a
per-app dependency list.

Supported dependencies live in the `dependencyProvisioners` registry in
`apptests/suites/dependencies.go`. To support a heavier dependency, add one
entry keyed by the name used in `metadata.yaml`:

```go
var dependencyProvisioners = map[string]func(context.Context) error{
	"cert-manager": provisionCertManager,
	"istio-helm":   provisionIstioCRDs,
	"your-dep":     provisionYourDep, // installs only the CRDs/controllers needed on Kind
}
```

An app naming a dependency with no provisioner fails fast with a message
pointing here, so the metadata and the registry can't silently drift.

## Apps needing bespoke setup

Most apps need nothing beyond listing (dependencies come from metadata). If an
app needs setup that neither template covers -- extra secrets, ConfigMap
patches, a non-standard readiness signal -- add a dedicated
`apptests/suites/<app>_test.go`:

1. Write a Ginkgo `Describe` block with `Label("<app>")` matching the
   directory name.
2. Drive the cluster through `harness.Default` (`SetupCluster`, `InstallApp`,
   `Client`, ...) and call `provisionDependencies(ctx, "<app>")` in `BeforeAll`
   -- test files depend only on the `harness` package, never on the underlying
   shared harness module.
3. Do **not** add the app to `enabledApps` or `customTestApps`; the dedicated
   file registers its own Ginkgo blocks. Still ensure CI matrix detection knows
   about it (list it in the appropriate slice or extend detection).

The same `just e2e-test <app> <version>` entrypoint works for all models.
