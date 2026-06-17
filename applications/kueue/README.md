# kueue

Kubernetes-native job queueing with quota management and all-or-nothing (gang)
admission for batch and AI/ML workloads.

Kueue does not replace the scheduler. It decides *whether and when* a job is
admitted to run (i.e. when its pods may be created), based on quotas, fair
sharing, and gang admission. This prevents resource deadlock and starvation on
shared clusters — especially expensive GPU clusters.

## Chart Source

The Kueue Helm chart is published natively as an OCI artifact. No additional
push step is required, and the chart bundles its CRDs (installed via
`install.crds: CreateReplace`).

| Field | Value |
|-------|-------|
| Chart OCI URL | `oci://registry.k8s.io/kueue/charts/kueue` |
| Namespace | `kueue-system` |

The pinned chart/app version lives in the per-version directory (e.g.
`0.x.0/helmrelease/helmrelease.yaml`), not here.

## Default Configuration

`helmrelease/cm.yaml` ships empty default values (`values.yaml: ""`), so the
upstream chart defaults apply. Those defaults are production-appropriate:

- **Controller image** — pulled from `registry.k8s.io/kueue/kueue` at the chart's
  pinned tag, `pullPolicy: IfNotPresent`.
- **Certificates** — internal cert management for the webhook (`enableCertManager: false`).
  No `cert-manager` dependency.
- **KueueViz dashboard** — disabled (`enableKueueViz: false`). Enabling it would add
  an nginx Ingress dependency; it is intentionally left off.
- **Queues** — **none.** Kueue installs the controller and CRDs but ships no
  `ClusterQueue`/`LocalQueue`/`ResourceFlavor`, because quotas are
  cluster-specific. See *Getting Started* to create them.

To override, edit `helmrelease/cm.yaml` or set values via the NKP app
configuration UI.

## Getting Started (hello world)

After install, create a flavor, a cluster-wide quota pool, and a namespaced
queue:

```yaml
apiVersion: kueue.x-k8s.io/v1beta2
kind: ResourceFlavor
metadata:
  name: default-flavor
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: ClusterQueue
metadata:
  name: smoke-cq
spec:
  namespaceSelector: {}
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: "cpu"
        nominalQuota: "2"
      - name: "memory"
        nominalQuota: "4Gi"
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: LocalQueue
metadata:
  name: smoke-lq
  namespace: default
spec:
  clusterQueue: smoke-cq
```

Submit a Job pointing at the queue (the `kueue.x-k8s.io/queue-name` label is what
makes Kueue manage it):

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: smoke-job
  namespace: default
  labels:
    kueue.x-k8s.io/queue-name: smoke-lq
spec:
  parallelism: 1
  completions: 1
  suspend: true
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: sleep
        image: registry.k8s.io/e2e-test-images/agnhost:2.53
        args: ["pause"]
        resources:
          requests: { cpu: "1", memory: "1Gi" }
```

Verify Kueue admitted it:

```bash
kubectl get workloads -n default        # a Workload appears; ADMITTED=True
kubectl get job smoke-job -o jsonpath='{.spec.suspend}'   # flips to false
kubectl get pods -n default             # pod runs
kubectl describe clusterqueue smoke-cq  # Pending/Admitted counters
```

Submit a second over-quota job to see queueing: it stays Pending until the first
job finishes and frees quota, then it is admitted automatically.

## GPU queueing

GPU support is runtime configuration only — no change to this catalog entry or
the chart. To queue GPU work:

- Label the `ResourceFlavor` to your GPU nodes (`spec.nodeLabels`).
- Add `nvidia.com/gpu` to the `ClusterQueue` `coveredResources` with a quota.
- Have the Job request `resources.limits: { nvidia.com/gpu: 1 }`.

This requires the cluster to actually have GPU worker nodes and a GPU device
plugin / NVIDIA GPU operator exposing `nvidia.com/gpu` as an allocatable
resource.

## Dependencies

None required by default (internal certs, no gateway/ingress). The optional
KueueViz dashboard — not enabled here — would require an nginx Ingress.

## Links

- [Kueue docs](https://kueue.sigs.k8s.io/docs/)
- [GitHub](https://github.com/kubernetes-sigs/kueue)
- [Helm chart reference](https://github.com/kubernetes-sigs/kueue/blob/main/charts/kueue/README.md)
