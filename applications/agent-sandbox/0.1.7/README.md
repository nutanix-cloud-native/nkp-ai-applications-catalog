# agent-sandbox

Kubernetes SIG [Agent Sandbox](https://github.com/kubernetes-sigs/agent-sandbox)
controller. It defines the `Sandbox` API (`agents.x-k8s.io`) that runtimes such
as OpenShell create sandboxes through. It has no UI and no front-end service.

## Chart Source

| Field | Value |
|-------|-------|
| Chart OCI URL | `oci://ghcr.io/nutanix-cloud-native/charts/agent-sandbox` |
| Chart tag | `0.1.7` |
| Controller namespace | `agent-sandbox-system` (created by the chart) |
| Upstream | `kubernetes-sigs/agent-sandbox`, `helm/` at commit `6cc854d` |

The chart is upstream, with two catalog changes:

- `Chart.yaml` links back to this catalog, and its version is `0.1.7`.
- `values.yaml` defaults `image.tag` to `v1.0.9`, because upstream has no default
  and fails to render without one.

The chart reference is defined in `helmrelease/helmrelease.yaml`.

## Default Configuration

`helmrelease/cm.yaml` pins the controller image to `v1.0.9`, the release
OpenShell 0.1.6 is tested against. Everything else uses upstream chart defaults.
Resource requests, limits and the leader-election flag are left at upstream
defaults. Override them through App Config Overrides.

The ServiceMonitor and PrometheusRule are created only when enabled, with
`metrics.serviceMonitor.enabled` and `metrics.prometheusRule.enabled`. Both are
off by default.

## CRDs

The chart ships four CRDs in its `crds/` directory:

- `sandboxes.agents.x-k8s.io`
- `sandboxclaims.extensions.agents.x-k8s.io`
- `sandboxtemplates.extensions.agents.x-k8s.io`
- `sandboxwarmpools.extensions.agents.x-k8s.io`

The HelmRelease sets `crds: CreateReplace` on install and on upgrade. Helm
applies the CRDs from the chart each time, so a new version's schema changes
land on upgrade. Helm never removes `crds/` on uninstall, so this keeps the
CRDs, and every `Sandbox` object stored under them, when the application is
uninstalled.

- **Uninstall** removes the controller, its RBAC and the namespace, and keeps
  the CRDs. This was tested on a workload cluster: the running sandbox kept its
  UID and stayed Ready while the controller was gone.
- **Upgrades** replace the CRDs before the controller changes. For example,
  `SandboxWarmPool` gains `readinessGracePeriodSeconds` in this version.

Only one application may own these CRDs. Do not install a second copy of Agent
Sandbox on the same cluster.

## Dependencies

No other catalog application is required. OpenShell 0.1.6 requires this
application (`requiredDependencies`), so enable Agent Sandbox first. Without the
CRDs and the controller, OpenShell's chart preflight fails with
`Agent Sandbox is required`.

## Verify

```bash
kubectl -n agent-sandbox-system get deploy agent-sandbox-controller
kubectl get crd | grep agents.x-k8s.io
kubectl get sandboxes -A
```

## Air-gap

The controller image listed in `helmrelease/extra-images.txt` must be mirrored
for air-gapped installs:

- `registry.k8s.io/agent-sandbox/agent-sandbox-controller:v1.0.9`

## Links

- [Agent Sandbox (upstream)](https://github.com/kubernetes-sigs/agent-sandbox)
- [Upstream Helm chart](https://github.com/kubernetes-sigs/agent-sandbox/tree/6cc854d8d1beb16ba279c512a6f3fd487eacb54c/helm)
- [OpenShell](https://github.com/NVIDIA/OpenShell)
