# NVIDIA Run:ai Cluster

NVIDIA Run:ai cluster components (operator, scheduler, workload controllers).
The cluster registers with a Run:ai control plane, either the
[`runai-control-plane`](../runai-control-plane/README.md) app on the same NKP
cluster or a remote control plane.

## Chart Source

The upstream chart is published by NVIDIA on NGC
(`https://helm.ngc.nvidia.com/nvidia/runai`, requires an NGC API key) and is
mirrored into our OCI registry.

| Field | Value |
|-------|-------|
| Upstream chart | `runai-cluster` |
| Mirrored OCI URL | `oci://ghcr.io/nutanix-cloud-native/nkp-ai-applications-catalog/charts/runai-cluster` |
| Chart version | `3.0.20` |

The cluster version must not be newer than the control-plane version, so keep
this app in step with `runai-control-plane`.

## Deployment Layout

| Item | Value |
|------|-------|
| Namespace | `runai` (required by Run:ai) |
| Helm release name | `runai-cluster` (required by Run:ai) |
| Ingress class | `kommander-traefik` (`clusterConfig.global.ingress.ingressClass`) |
| TLS secret | `runai-cluster-domain-tls-secret` in `runai` (remote control plane) |
| CA trust | `global.customCA` is enabled by default; reads `runai-ca.pem` from the optional `runai-ca-cert` secret in `runai` |
| Defaults | Ingress class, OpenShift mode, and CA trust are set in `helmrelease/cm.yaml`; `global.fipsMode` is already `off` upstream |
| OpenShift mode | `Disabled` |

The chart also creates the `runai-reservation` and `runai-scale-adjust`
namespaces and installs the `run.ai/v1` `Cluster` CRD.

Run:ai images are pulled anonymously from `nvcr.io/nvidia/runai-oss`; the
bundled KAI components come from `ghcr.io/kai-scheduler`.

## KAI Scheduler Conflict

Starting with 3.0, the chart bundles KAI Scheduler (`kai-resource-management`
subchart) and installs the same CRDs as the `kai-scheduler` catalog app,
including `queues.scheduling.run.ai`, `podgroups.scheduling.run.ai`,
`bindrequests.scheduling.run.ai`, `configs.kai.scheduler`,
`schedulingshards.kai.scheduler`, and `topologies.kai.scheduler`. Do not
deploy `runai-cluster` and `kai-scheduler` on the same cluster.

## Dependencies

| Platform app | Required | Notes |
|--------------|----------|-------|
| `nvidia-gpu-operator` | Yes | Run:ai supports GPU Operator 25.10 to 26.3 |
| `kube-prometheus-stack` | Yes | Provides the Prometheus Operator CRDs; Run:ai creates its own Prometheus CR in `runai` |
| `traefik` | Yes | Ingress for the cluster URL and workload endpoints |
| `knative` | No | Standard inference workloads (Knative Serving 1.19 to 1.21) |

## Install Flow

Only the values that identify this cluster and its control plane are
overrides; everything else is a default.

1. In the Run:ai UI, create the cluster and copy the values from the
   generated Helm command.
2. Make the control-plane and cluster FQDNs resolve from this cluster. For
   names that are not in DNS, add them to CoreDNS (`hosts { <LB IP> <name>;
   fallthrough }`). The cluster FQDN points at the `kommander-traefik` load
   balancer; for a remote control plane, also create the `runai` namespace and
   the `runai-cluster-domain-tls-secret`.
3. If the control plane uses a private CA (the `runai-control-plane` app does
   by default), give the cluster that CA. Export it on the control-plane
   cluster and create the secret here:

   ```bash
   kubectl get secret runai-backend-tls -n runai-backend \
     -o jsonpath='{.data.ca\.crt}' | base64 -d > runai-ca.pem
   kubectl create namespace runai
   kubectl create secret generic runai-ca-cert -n runai \
     --from-file=runai-ca.pem=runai-ca.pem
   ```

   Skip this for a public CA.
4. Enable the app with these overrides:

   ```yaml
   controlPlane:
     url: runai.mycorp.local
     bootstrapToken: <bootstrap-token>   # or clientSecret: <client-secret>
   cluster:
     uid: <cluster-uid>
     url: https://runai-cluster.mycorp.local
   ```

   The bootstrap token expires after about 2 hours, and the chart's
   pre-upgrade hook reuses it, so a later upgrade needs a fresh token from the
   UI (or use `clientSecret` instead).
5. Wait for the cluster to show as **Connected** in the Run:ai UI.

## GPU Fractioning

Fractional GPU needs these on the GPU nodes, otherwise the cluster shows
`not ready: MpsdReady`:

- NVIDIA driver `r615` or newer (the `mpsd` daemon uses the MPS v3 interface).
  NKP GPU node images ship an older driver (580.x), so build the image with
  `nvidia_driver_version` set to a 615+ release.
- GPU Operator with the device plugin enabled (`devicePlugin.enabled: true`;
  it is mutually exclusive with DRA) and container toolkit `v1.20.1` or newer.
- containerd 2.0+ with NRI.

## Open Items

- Confirm NVIDIA's redistribution terms allow hosting the chart in our public
  GHCR namespace.
- The operator pulls additional operand images at runtime that are not in the
  rendered chart; list them in `helmrelease/extra-images.txt` before claiming
  air-gapped support.
- Validate on an NKP GPU cluster: registration, Prometheus remote write, and a
  GPU training workload.

## Links

- [Install the cluster](https://run-ai-docs.nvidia.com/self-hosted/getting-started/installation/install-using-helm/helm-install)
- [System requirements](https://run-ai-docs.nvidia.com/self-hosted/getting-started/installation/install-using-helm/system-requirements)
