# KAI Scheduler Test Notes

This document captures what we validated on the test cluster and how.

## 1) KAI Scheduler: what it is and key understanding

KAI Scheduler is a Kubernetes-native scheduler focused on AI and ML workloads, especially queue-based and GPU-oriented scheduling use cases. It runs alongside the default Kubernetes scheduler and handles only workloads that explicitly target it.

Key points we validated/confirmed:

- KAI Scheduler is installed as its own control-plane components in the `kai-scheduler` namespace.
- It introduces queue-based scheduling primitives (for example, `Queue` CRs).
- Workloads are scheduled by KAI only when they set:
  - `spec.schedulerName: kai-scheduler`
  - queue label, such as `kai.scheduler/queue: default-queue`
- It can be installed and tested on clusters without GPUs.
- Without physical GPUs on nodes, `nvidia.com/gpu` allocatable stays empty, so GPU workload scheduling cannot be validated, even if NVIDIA GPU Operator is installed.

## 2) How KAI Scheduler was deployed

Cluster access used:

```bash
export KUBECONFIG="/Users/navid.malekghaini/project/workload-cluster-01.conf"
```

Install command used:

```bash
helm upgrade -i kai-scheduler \
  oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler \
  -n kai-scheduler \
  --create-namespace \
  --version v0.15.2
```

Post-install verification used:

```bash
kubectl get pods -n kai-scheduler
kubectl wait --for=condition=Available deployment --all -n kai-scheduler --timeout=180s
kubectl get crd | rg -i "kai\\.scheduler|queues|podgroups"
kubectl get queue -A
```

Observed outcome:

- Helm release installed successfully (`STATUS: deployed`).
- KAI deployments became available:
  - `admission`
  - `binder`
  - `kai-operator`
  - `kai-scheduler-default`
  - `pod-grouper`
  - `podgroup-controller`
  - `queue-controller`
- KAI-related CRDs were present (including queue and podgroup types).
- Default queue hierarchy existed:
  - `default-parent-queue`
  - `default-queue`

## 3) How the smoke test was performed

Because workloads should not be submitted to `kai-scheduler` namespace, a dedicated test namespace was created.

Create namespace:

```bash
kubectl create namespace kai-test --dry-run=client -o yaml | kubectl apply -f -
```

Apply CPU-only test pod that targets KAI Scheduler and default queue:

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

Verify scheduling result:

```bash
kubectl get pod -n kai-test kai-cpu-smoke -o wide
kubectl describe pod -n kai-test kai-cpu-smoke | rg -n "Scheduler|Node:|Events:|Scheduled|kai-scheduler"
```

Observed smoke test result:

- Pod reached `Running`.
- Event confirmed scheduling by KAI Scheduler:
  - `Successfully assigned pod kai-test/kai-cpu-smoke ...`
  - scheduler shown as `kai-scheduler`.

## 4) GPU-cluster validation run

Cluster access used:

```bash
export KUBECONFIG="/Users/navid.malekghaini/project/gpu-workload-cluster-01.conf"
```

KAI deployment status on this cluster:

- KAI Scheduler `v0.15.2` installed successfully in `kai-scheduler`.
- All KAI deployments became `Available`.
- Default queues were present (`default-parent-queue`, `default-queue`).

CPU smoke test result on this cluster:

- `kai-cpu-smoke` reached `Running`.
- Event confirmed scheduling by `kai-scheduler`.

GPU smoke pod applied:

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

GPU smoke result on this cluster:

- `kai-gpu-smoke` remained `Pending`.
- KAI scheduler event:
  - `No node in the default node-pool has GPU resources.`
- Node allocatable checks showed empty `nvidia.com/gpu` on all nodes at test time.

## Notes and conclusions

- `workload-cluster-01.conf`:
  - No allocatable GPUs on nodes.
  - NVIDIA GPU Operator components present in `workload-cluster-01-jvslk`.
  - CPU scheduling by KAI validated; GPU scheduling not testable.
- `gpu-workload-cluster-01.conf`:
  - NVIDIA GPU Operator pod present in `gpu-workspace-7hhhv`.
  - CPU scheduling by KAI validated.
  - GPU pod still unschedulable due to missing node-level GPU allocatable resources.

Overall: KAI Scheduler installation and queue-based scheduling are validated. GPU scheduling is blocked by cluster GPU resource exposure, not by KAI installation.
