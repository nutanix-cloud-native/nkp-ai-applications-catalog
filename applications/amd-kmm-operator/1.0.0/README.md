# AMD KMM Operator

Shared Kernel Module Management (KMM) operator for AMD GPU and Network operators.

## What This Component Does

1. **Installs KMM** — a single, pinned KMM instance shared by both `amd-gpu-operator` and `amd-network-operator`. Consumers disable their embedded KMM subchart (`kmm.enabled=false`).
2. **Registry Credential Projection** — a CronJob reads a user-provided `kmm-registry-credentials` Secret and projects it into a `docker-registry` Secret (`kmm-registry-dockerconfig`) usable by KMM for image push/pull.
3. **Node Containerd Trust** — a DaemonSet writes the registry's `hosts.toml` and optional CA certificate into `/etc/containerd/certs.d/<registry-url>/` on every node, so kubelet can pull built driver images without a containerd restart.

## Prerequisites

If you are using a private container registry for driver images, create the credentials secret **before** installing this component:

```bash
kubectl create secret generic kmm-registry-credentials \
  --namespace=<workspace-namespace> \
  --from-literal=registry-url=registry.example.com:5000 \
  --from-literal=username=admin \
  --from-literal=password='<password>' \
  --from-file=ca.crt=/path/to/ca.crt    # optional; omit if registry uses a public CA
```

Required keys:
| Key | Required | Description |
|---|---|---|
| `registry-url` | Yes | Registry hostname and optional port (DNS or IP) |
| `username` | Yes | Registry username |
| `password` | Yes | Registry password |
| `ca.crt` | No | PEM-encoded CA certificate for TLS trust |

If the secret is absent, KMM is still installed and functional — registry plumbing is simply not created.

## Install / Uninstall Order

**Install:** `amd-kmm-operator` first, then `amd-gpu-operator` and/or `amd-network-operator`.

**Uninstall:** Consumers first (`amd-gpu-operator`, `amd-network-operator`), then `amd-kmm-operator`.

## CRD Lifecycle

KMM CRDs are installed with `crds: CreateReplace` and are **preserved** on uninstall by default (Helm does not delete CRDs). This prevents data loss if consumers still have `Module` or `NodeModulesConfig` resources.

## Self-Healing Reconciliation

The registry reconciler CronJob runs every 5 minutes and is fully idempotent:
- If `kmm-registry-credentials` appears after initial install, the plumbing is created automatically.
- If the credentials secret is updated, the dockerconfig and DaemonSet are reconciled on the next cycle.
- If resources are accidentally deleted, they are recreated.
