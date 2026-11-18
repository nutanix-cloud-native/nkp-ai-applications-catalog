# openshell

NVIDIA OpenShell is a sandboxed runtime for autonomous AI agents. The gateway
creates isolated sandbox pods and enforces filesystem, network, and credential
policy on every agent workload through a trusted supervisor.

The catalog deploys the upstream chart unmodified from
`oci://ghcr.io/nvidia/openshell/helm-chart` into the dedicated `openshell`
namespace. Upstream marks the Kubernetes deployment path as experimental.

## Prerequisites

### Agent Sandbox

OpenShell provisions sandboxes through the Kubernetes SIG
[Agent Sandbox](https://github.com/kubernetes-sigs/agent-sandbox) API (v1.0.9).
The application vendors that release in `0.1.6/agent-sandbox/sandbox.yaml` and
applies it with its own Flux Kustomization `<release>-agent-sandbox`. The
OpenShell HelmRelease waits for it (`dependsOn`), so there is no manual install
step.

- The Agent Sandbox Kustomization has `prune: false`. Uninstalling OpenShell keeps
  the CRD and the controller. This is intentional: deleting the CRD would delete
  every Sandbox in the cluster.
- The consequence is that the CRD is left behind after uninstall. Remove it by
  hand only when no Sandbox is needed: `kubectl delete crd sandboxes.agents.x-k8s.io`.
- Exactly one application may own `sandboxes.agents.x-k8s.io`. Do not ship a
  second Agent Sandbox install alongside this one.

If the CRD exists but was installed another way, the chart's preflight check still
passes, and Flux adopts the objects on first apply. Keep the preflight enabled
(`agentSandbox.preflight.enabled`, default `true`). Air-gapped clusters need
`registry.k8s.io/agent-sandbox/agent-sandbox-controller:v1.0.9` mirrored; it is
listed in `helmrelease/extra-images.txt`.

### NetworkPolicy enforcement

The CNI must enforce ingress **and** egress `NetworkPolicy` in the sandbox
namespace. OpenShell creates the policies, but Kubernetes accepts them even when
nothing enforces them, and sandboxes could then bypass supervisor network
policy. Cilium, the NKP default CNI, enforces both.

### Storage

The gateway StatefulSet requests a 1Gi `openshell-data` PVC for its SQLite
database, and each sandbox requests a 2Gi workspace PVC. Both use the default
StorageClass. On clusters without one, set these in **App Config Overrides**
(the gateway claim is immutable after install):

```yaml
server:
  dataStorageClass: <storage-class>
  workspaceStorageClass: <storage-class>
```

## Access

The gateway is a ClusterIP Service on port 8080 (gRPC over mTLS). With the
catalog defaults (client CA configured, no OIDC issuer), the gateway
authenticates CLI users from the client certificate the PKI hook generates.
For local evaluation, copy that bundle and port-forward the gateway:

```bash
mkdir -p ~/.config/openshell/gateways/k8s/mtls
kubectl -n openshell get secret openshell-client-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > ~/.config/openshell/gateways/k8s/mtls/ca.crt
kubectl -n openshell get secret openshell-client-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > ~/.config/openshell/gateways/k8s/mtls/tls.crt
kubectl -n openshell get secret openshell-client-tls -o jsonpath='{.data.tls\.key}' | base64 -d > ~/.config/openshell/gateways/k8s/mtls/tls.key

kubectl -n openshell port-forward svc/openshell 8080:8080
```

In another terminal, register the gateway with the
[`openshell` CLI](https://docs.nvidia.com/openshell/about/installation) and
check it. `--local` makes the CLI use the mTLS bundle above; without it, an
`https://` endpoint is treated as an edge-authenticated gateway and the CLI
opens a browser login instead:

```bash
openshell gateway add https://127.0.0.1:8080 --name k8s --local
openshell status
```

The server certificate includes `127.0.0.1` and `localhost`, so this works over
the port-forward. Anyone holding the client bundle can use the gateway; for
shared environments configure OIDC (`server.oidc.*`) and expose the gateway
through Gateway API (`grpcRoute.*`) or an access proxy, per the upstream
[access control guide](https://docs.nvidia.com/openshell/kubernetes/access-control).

## Smoke Test

```bash
# Gateway and PKI hook
kubectl -n openshell get helmrelease,statefulset,pod
kubectl -n openshell get secret openshell-server-tls openshell-client-tls openshell-jwt-keys

# Gateway is healthy
kubectl -n openshell rollout status statefulset/openshell
kubectl -n openshell logs statefulset/openshell --tail=20

# End to end: run a throwaway sandbox (after registering the CLI, see Access)
openshell sandbox create --name smoke --no-keep -- sh -c 'echo hello from openshell; exit 0'
kubectl -n openshell get sandboxes.agents.x-k8s.io,pods
```

## Monitoring

The gateway serves Prometheus metrics on the `metrics` port (9090) of the
`openshell` Service. The chart has no ServiceMonitor or Service label values,
so `helmrelease/helmrelease.yaml` uses a Flux `postRenderers` patch to add
`servicemonitor.kommander.mesosphere.io/path: metrics` to that Service. The NKP
Prometheus (kube-prometheus-stack) already has a ServiceMonitor,
`dkp-service-monitor-metrics`, that scrapes the `metrics` port of every Service
with that label (Harbor uses the same mechanism). Because the app ships only a
label, it installs cleanly in workspaces without kube-prometheus-stack.

Check it:

```bash
kubectl -n openshell get svc openshell --show-labels   # servicemonitor.kommander.mesosphere.io/path=metrics
kubectl -n kommander port-forward svc/kube-prometheus-stack-prometheus 19090:9090
# then query: up{namespace="openshell"}   (1 = scraped)
```

Useful series:

| Metric | Meaning |
|---|---|
| `openshell_server_grpc_requests_total{method,code}` | Gateway API calls, for example `CreateSandbox`, `DeleteSandbox` |
| `openshell_server_grpc_request_duration_seconds` | API latency |
| `openshell_server_supervisor_sessions` | Connected sandbox supervisors |
| `openshell_server_readiness_database_healthy` | 1 when the gateway's SQLite database is healthy |
| `openshell_server_relay_pending`, `openshell_server_relay_rejected_total` | Relay (SSH/TCP forwarding) backlog and rejections |
| `openshell_supervisor_policy_apply_results_total` | Policy applications reported by sandboxes |

For example, the sandbox creation rate is
`sum(rate(openshell_server_grpc_requests_total{method="CreateSandbox"}[5m]))`.

## Images

All images are listed in `artifacts.yaml` for air-gapped bundles. The gateway
image is rendered by the chart; the supervisor, sandbox runtime, and default
sandbox base images are referenced only in the gateway's TOML config, so they
are declared in `helmrelease/extra-images.txt`.

## Icon

The `icon` field in `metadata.yaml` is the base64-encoded upstream favicon:

```bash
curl -sL https://raw.githubusercontent.com/NVIDIA/OpenShell/v0.1.6/docs/brand/assets/favicon.svg \
  | base64 | tr -d '\n'
```

## Links

- [Documentation](https://docs.nvidia.com/openshell/)
- [GitHub (OpenShell)](https://github.com/NVIDIA/OpenShell)
- [Helm chart](https://github.com/NVIDIA/OpenShell/tree/v0.1.6/deploy/helm/openshell)
- [Agent Sandbox](https://github.com/kubernetes-sigs/agent-sandbox)
