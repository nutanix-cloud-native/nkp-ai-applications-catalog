# ray-cluster

Deploy and manage Ray runtime workloads (head/worker pods) on NKP using the
Ray Cluster Helm chart.

## Chart Source

| Field | Value |
|-------|-------|
| Chart OCI URL | `oci://ghcr.io/nutanix-cloud-native/charts/ray-cluster` |
| Chart tag | `1.7.0` |
| Target namespace | `kuberay` |

The chart reference and pinned tag are defined in
`helmrelease/helmrelease.yaml`.

## Default Configuration

This catalog entry does not ship a defaults ConfigMap for Helm values.
The deployment uses upstream chart defaults, and user-provided values are
injected by the app deployment controller at deploy time.

## Dependencies

`requiredDependencies` includes:

- `kuberay`

Install `kuberay` first so the Ray CRDs and operator are present before
deploying `ray-cluster`.

## Profiling Prerequisites

Ray dashboard CPU profiling and stack traces may require `SYS_PTRACE` in Ray
pods. Add security context overrides for head/worker pods when these
diagnostics are needed.

Memory profiling can also require debugger tooling (`gdb` or `lldb`) in the Ray
image.

## Links

- [Ray on Kubernetes docs](https://docs.ray.io/en/latest/cluster/kubernetes/index.html)
- [KubeRay project](https://github.com/ray-project/kuberay)
