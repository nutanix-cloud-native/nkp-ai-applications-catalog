# kai-scheduler

Kubernetes-native scheduler for AI and ML workloads with queue-based and
fair-share scheduling capabilities.

## Chart Source

The KAI Scheduler Helm chart is published natively as an OCI artifact. No
additional push step is required.

| Field | Value |
|-------|-------|
| Chart OCI URL | `oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler` |
| Version | `v0.15.2` |

## Dependencies

KAI Scheduler has no hard catalog dependency declared in `requiredDependencies`.

Prerequisites for workload behavior:

- For CPU scheduling tests, no GPU prerequisite is needed.
- For GPU scheduling tests, cluster nodes must expose allocatable
  `nvidia.com/gpu` resources.

## Smoke Test Validation

This section captures what was validated and how.

### Key behavior validated

- KAI Scheduler installs as dedicated control-plane components in the
  `kai-scheduler` namespace.
- Queue resources are created and used for scheduling decisions.
- Workloads are handled by KAI only when they include:
  - `spec.schedulerName: kai-scheduler`
  - `kai.scheduler/queue: default-queue` (or another valid queue).
- CPU workload scheduling path is functional.
- GPU scheduling depends on node-level `nvidia.com/gpu` capacity exposure.

### Installation and verification commands used

```bash
helm upgrade -i kai-scheduler \
  oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler \
  -n kai-scheduler \
  --create-namespace \
  --version v0.15.2

kubectl get pods -n kai-scheduler
kubectl wait --for=condition=Available deployment --all -n kai-scheduler --timeout=180s
kubectl get crd | rg -i "kai\\.scheduler|queues|podgroups"
kubectl get queue -A
```

Observed install outcome:

- Helm release reached `STATUS: deployed`.
- Core KAI components reached `Available`:
  - `admission`
  - `binder`
  - `kai-operator`
  - `kai-scheduler-default`
  - `pod-grouper`
  - `podgroup-controller`
  - `queue-controller`
- Default queue hierarchy existed:
  - `default-parent-queue`
  - `default-queue`

### Smoke test manifests used

Create test namespace:

```bash
kubectl create namespace kai-test --dry-run=client -o yaml | kubectl apply -f -
```

CPU smoke pod:

```bash
kubectl apply -n kai-test -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: kai-cpu-smoke
  labels:
    kai.scheduler/queue: default-queue
spec:
  schedulerName: kai-scheduler
  restartPolicy: Never
  containers:
  - name: pause
    image: registry.k8s.io/pause:3.10
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 100m
        memory: 128Mi
EOF
```

GPU smoke pod:

```bash
kubectl apply -n kai-test -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: kai-gpu-smoke
  labels:
    kai.scheduler/queue: default-queue
spec:
  schedulerName: kai-scheduler
  restartPolicy: Never
  containers:
  - name: cuda
    image: nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda12.5.0
    resources:
      limits:
        nvidia.com/gpu: "1"
EOF
```

### Cluster test results

#### `workload-cluster-01.conf`

- CPU smoke pod reached `Running`.
- Event confirmed scheduling by `kai-scheduler`.
- Nodes exposed no allocatable `nvidia.com/gpu`.
- GPU scheduling not testable due to missing GPU capacity.

#### `gpu-workload-cluster-01.conf`

- CPU smoke pod reached `Running` and was scheduled by `kai-scheduler`.
- GPU smoke pod remained `Pending`.
- Scheduler event reported:
  - `No node in the default node-pool has GPU resources.`
- Autoscaler also reported node group at max size during attempts.

### Conclusion

KAI Scheduler installation and queue-based CPU scheduling are validated.
GPU scheduling remains blocked by cluster GPU resource exposure/capacity, not by
KAI deployment manifests.

## Links

- [GitHub (KAI Scheduler)](https://github.com/kai-scheduler/KAI-Scheduler)
- [Releases](https://github.com/kai-scheduler/KAI-Scheduler/releases)
- [Quickstart](https://github.com/kai-scheduler/KAI-Scheduler/tree/main/docs/quickstart)
