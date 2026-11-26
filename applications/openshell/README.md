# openshell

NVIDIA OpenShell is a sandboxed runtime for autonomous AI agents. The gateway
creates isolated sandbox pods and enforces filesystem, network, and credential
policy on every agent workload through a trusted supervisor.

## Chart Source

| Field | Value |
|-------|-------|
| Chart OCI URL | `oci://ghcr.io/nvidia/openshell/helm-chart` |
| Chart tag | `0.1.6` |
| Target namespace | `openshell` |

The chart reference and pinned tag are defined in `helmrelease/helmrelease.yaml`.
The chart is upstream, unmodified. Upstream marks the Kubernetes deployment path
as experimental.

## Default Configuration

`helmrelease/cm.yaml` sets the gateway resource requests and limits and a
`ClusterIP` Service. Everything else uses upstream chart defaults. Override any
value through App Config Overrides.

## Dependencies

`requiredDependencies` includes:

- `agent-sandbox` (0.1.7). It installs the `sandboxes.agents.x-k8s.io` CRD and
  the controller that OpenShell creates sandboxes through. Enable it before
  OpenShell. Without it, the chart's preflight check fails the HelmRelease with
  `Agent Sandbox is required but neither agents.x-k8s.io/v1beta1 nor
  agents.x-k8s.io/v1alpha1 is served by this cluster`. Leave
  `agentSandbox.preflight.enabled` at its default (`true`).

Other requirements:

- A CNI that enforces ingress and egress `NetworkPolicy` in the sandbox
  namespace. Cilium, the NKP default CNI, does. Without enforcement, sandboxes
  could bypass supervisor network policy.
- A default StorageClass. The gateway requests a 1Gi `openshell-data` PVC for
  its SQLite database, and each sandbox requests a 2Gi workspace PVC. On
  clusters without a default, set `server.dataStorageClass` and
  `server.workspaceStorageClass` in App Config Overrides before the first
  install, because the gateway claim is immutable.

## Access

The gateway is a `ClusterIP` Service on port 8080 (gRPC over mTLS). The usage
steps are in the application overview (`metadata.yaml`, "How to use").

## Monitoring

The gateway serves Prometheus metrics on the `metrics` port (9090) of the
`openshell` Service. `helmrelease/helmrelease.yaml` adds the
`servicemonitor.kommander.mesosphere.io/path: metrics` label to that Service
with a Flux `postRenderers` patch, so the NKP Prometheus scrapes it. Series
include `openshell_server_grpc_requests_total`,
`openshell_server_supervisor_sessions` and
`openshell_server_readiness_database_healthy`.

## Links

- [Documentation](https://docs.nvidia.com/openshell/)
- [GitHub (OpenShell)](https://github.com/NVIDIA/OpenShell)
- [Helm chart](https://github.com/NVIDIA/OpenShell/tree/v0.1.6/deploy/helm/openshell)
- [Agent Sandbox](https://github.com/kubernetes-sigs/agent-sandbox)
