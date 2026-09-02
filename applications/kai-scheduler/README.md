# kai-scheduler

<p align="center">
  <img src="https://github.com/kai-scheduler.png" alt="KAI Scheduler icon" width="120" />
</p>

Kubernetes-native scheduler for AI and ML workloads with queue-based and fair-share scheduling capabilities.

## Table of Contents

- [Introduction](#introduction)
- [Foundational Features](#foundational-features)
  - [Batch Scheduling & Gang Scheduling](#batch-scheduling-gang-scheduling)
  - [Bin-Packing & Spread Scheduling](#bin-packing-spread-scheduling)
  - [Topology-Aware Scheduling (TAS) & Hierarchical PodGroups](#topology-aware-scheduling-tas-hierarchical-podgroups)
  - [Dynamic Resource Allocation (DRA) & GPU Sharing](#dynamic-resource-allocation-dra-gpu-sharing)
  - [Fairness & Resource Distribution](#fairness-resource-distribution)
  - [Workload Consolidation & Elasticity](#workload-consolidation-elasticity)
- [How it fits together](#how-it-fits-together)
- [What KAI Scheduler Solves](#what-kai-scheduler-solves)
- [Relationship with Kueue](#relationship-with-kueue)
- [Further Questions](#further-questions)
  - [Q: Can KAI Scheduler run alongside the default Kubernetes scheduler?](#q-can-kai-scheduler-run-alongside-the-default-kubernetes-scheduler)
  - [Q: Does KAI support dynamic cloud auto-scalers?](#q-does-kai-support-dynamic-cloud-auto-scalers)
  - [Q: How does it handle workload priorities?](#q-how-does-it-handle-workload-priorities)
  - [Q: Is KAI only for NVIDIA GPUs?](#q-is-kai-only-for-nvidia-gpus)
  - [Q: Does it integrate with Ray?](#q-does-it-integrate-with-ray)
  - [Q: How much testing can be done on CPU-only clusters?](#q-how-much-testing-can-be-done-on-cpu-only-clusters)
  - [Q: How many GPU nodes are needed to validate GPU workloads?](#q-how-many-gpu-nodes-are-needed-to-validate-gpu-workloads)
- [Chart Source](#chart-source)
- [Dependencies](#dependencies)
- [Smoke Test Validation](#smoke-test-validation)
- [Links](#links)

## Introduction

KAI Scheduler is a robust, efficient, and scalable Kubernetes-native scheduler designed specifically to optimize GPU resource allocation for AI and machine learning workloads. Built on top of `kube-batch`, it is an open-source CNCF sandbox project.

The problem it solves: Managing large-scale GPU clusters (thousands of nodes) with high-throughput workloads requires advanced placement logic that the default Kubernetes scheduler lacks. KAI handles the entire AI lifecycle, from small interactive jobs to massive distributed training and inference, while ensuring resource fairness and optimal allocation.

It does not have to be the only scheduler; it can run alongside other schedulers installed on the cluster.

## Foundational Features

KAI Scheduler introduces several advanced scheduling capabilities tailored for AI and hardware:

### Batch Scheduling & Gang Scheduling

Ensures that all pods in a group are scheduled simultaneously or not at all (all-or-nothing). This prevents partial allocation deadlocks where half a job runs and holds GPUs while the rest wait.

*Why it is useful: A distributed training job might require 16 GPUs to run. If the scheduler places 14 pods and leaves 2 pending because the cluster is full, those 14 GPUs sit completely idle, burning money without doing any compute work. Gang scheduling ensures you only consume resources when the job can actually execute.*

*ELI5: Like a group of friends refusing to be seated until a table big enough for all of them is ready, ensuring they do not take up smaller tables while waiting for latecomers.*

### Bin-Packing & Spread Scheduling

Optimizes node usage by either minimizing fragmentation (bin-packing) or increasing resiliency and load balancing (spread scheduling).

*Why it is useful: Bin-packing groups small jobs onto the fewest nodes possible. This leaves entirely empty nodes available so that massive, multi-GPU training jobs have the contiguous space they need to run. It also allows cloud auto-scalers to spin down completely empty nodes to save money.*

*ELI5: Bin-packing is like seating as many people as possible in one corner of the restaurant so you have a huge empty space saved for a big party later. Spread scheduling is like seating parties far apart so the waiters are not crowded in one spot.*

### Topology-Aware Scheduling (TAS) & Hierarchical PodGroups

Optimizes pod placement by understanding the physical layout and network topology of the cluster. It supports multi-level workloads, making it ideal for distributed and disaggregated architectures like Dynamo/Grove.

*Why it is useful: GPUs that are physically connected on the same motherboard or switch (e.g., via NVLink or PCIe) can share data exponentially faster than GPUs communicating across the network. TAS ensures pods that need to talk to each other frequently are placed on the exact same physical hardware island, drastically reducing latency and training time.*

*ELI5: Like seating a large party at adjacent tables so they can easily talk to each other without having to shout across the entire restaurant.*

### Dynamic Resource Allocation (DRA) & GPU Sharing

Supports vendor-specific hardware resources (like NVIDIA GB200/GB300) through Kubernetes ResourceClaims. It also allows multiple workloads to efficiently share single or multiple GPUs, maximizing expensive hardware utilization.

*Why it is useful: Not every AI workload needs a full 80GB GPU. Inference workloads or Jupyter notebooks often need just a fraction of the compute power. DRA and sharing allow administrators to slice up these expensive cards safely, ensuring high utilization instead of wasting 90% of a card's capacity on a small workload.*

*ELI5: Like letting two small groups share one very large booth if they do not mind, rather than leaving half the booth empty.*

### Fairness & Resource Distribution

Uses policies like Dominant Resource Fairness (DRF) and Time-based Fairshare (which considers historical usage and time decay) to ensure equitable distribution. It also supports two-level queue hierarchies for flexible organizational control over quotas and limits.

*Why it is useful: In a shared cluster, one aggressive team could submit a massive backlog of jobs and block all other teams from getting compute time. Fairness policies ensure every team gets the GPU time they paid for, and Time-based Fairshare ensures that if a team did not use their quota yesterday, they get priority to catch up today.*

*ELI5: If one team has not eaten here in a month, they get priority seating today over the team that comes in and eats here every single night.*

### Workload Consolidation & Elasticity

Intelligently reallocates running workloads to reduce fragmentation and dynamically scales workloads within defined minimum and maximum thresholds.

*Why it is useful: Over time, as jobs finish and new ones start, a cluster becomes "Swiss cheese" with small pockets of unused GPUs scattered across different nodes. Consolidation automatically defragments the cluster by moving flexible workloads around, opening up large contiguous blocks for big training jobs.*

*ELI5: If people leave and tables open up, the host might ask a few parties to shift over so that a massive new space opens up for a giant group.*

## How it fits together

When a complex AI workload is submitted, KAI Scheduler looks at the priority, the required gang-scheduling constraints, and the hardware topology. It uses bin-packing or spread scheduling to place the workload optimally, ensuring that teams use their fair share over time and that GPU utilization is maximized without fragmentation.

## What KAI Scheduler Solves

* **Hardware Topology Optimization:** Distributed AI workloads need pods close together to reduce network latency. KAI's Topology-Aware Scheduling ensures optimal physical placement.
* **Complex Gang Scheduling:** Prevents deadlock by ensuring large, multi-component jobs get all their resources at once.
* **Fairness Over Time:** Instead of just pointing out who is using what *right now*, Time-based Fairshare looks at historical usage so a team that was idle yesterday can catch up today.
* **Hardware Utilization:** Through bin-packing, Workload Consolidation, and GPU sharing, KAI ensures that expensive GPU nodes are fully utilized rather than sitting partially empty.

## Relationship with Kueue

Kueue and KAI Scheduler do not contradict each other. In fact, they work perfectly together as complementary layers in the Kubernetes AI stack.

* **Kueue is the Admission Controller (The Host):** It manages quotas, waitlists, and cross-team borrowing. It decides *when* a job is allowed to enter the cluster based on available budgets.
* **KAI Scheduler is the Placement Engine (The Seating Arranger):** Once Kueue admits a job, KAI takes over to decide *where* those pods should physically go. It handles the actual binding to hardware, optimizing for GPU interconnects, bin-packing, and topology.

When used together, Kueue ensures teams play fair with quotas, and KAI ensures the jobs that do run are placed as efficiently as possible on the expensive GPU hardware.

## Further Questions

### Q: Can KAI Scheduler run alongside the default Kubernetes scheduler?

A: Yes. It can run alongside other schedulers installed on the cluster. You can specify which workloads should be handled by KAI.

### Q: Does KAI support dynamic cloud auto-scalers?

A: Yes. It is fully compatible with dynamic cloud infrastructures (including auto-scalers like Karpenter) as well as static on-premises deployments.

### Q: How does it handle workload priorities?

A: KAI supports workload priority within queues and uniquely separates workload priority from preemptibility, treating them as two independent policies. It also includes a `min-guaranteed-runtime` to ensure a workload is not preempted too quickly after starting.

### Q: Is KAI only for NVIDIA GPUs?

A: While highly optimized for NVIDIA GPUs (requiring the NVIDIA GPU-Operator for GPU scheduling), its Dynamic Resource Allocation (DRA) support extends to vendor-specific hardware resources, including AMD.

### Q: Does it integrate with Ray?

A: Yes. KAI Scheduler is natively integrated for Ray workloads on Kubernetes (KubeRay), making it highly effective for orchestrating complex agentic pipelines and distributed AI computing.

### Q: How much testing can be done on CPU-only clusters?

A: A significant portion of KAI's core queueing and placement logic can be tested on CPU-only clusters. Features like batch/gang scheduling (all-or-nothing), hierarchical queues, Time-based Fairshare, workload consolidation, and basic bin-packing or spread scheduling are resource-agnostic and work perfectly with standard CPU and memory requests.

**What you cannot test on CPU-only (needs real GPUs):** Because KAI is the actual Kubernetes scheduler (meaning it actually binds pods to hardware), it relies on real node capacities, labels, and the GPU-Operator. Without real GPUs, you cannot test:

* **Topology-Aware Scheduling (TAS):** Optimizing placement based on GPU interconnects (like NVLink/PCIe) requires real GPU topology data.
* **GPU Sharing:** Allowing multiple workloads to efficiently share single or multiple GPUs.
* **Dynamic Resource Allocation (DRA):** Testing vendor-specific hardware claims (e.g., NVIDIA GB200/GB300 compute resources).
* **Real GPU Execution:** The physical binding and execution of GPU-dependent AI jobs.

### Q: How many GPU nodes are needed to validate GPU workloads?

A: The required hardware depends on which advanced KAI features you need to prove:

* **Basic GPU Allocation & GPU Sharing:** 1 node with 1 GPU is enough to demonstrate KAI scheduling a job to a GPU or splitting a single GPU among multiple pods.
* **Gang Scheduling & Resource Contention:** At least 2 GPUs (either 2 single-GPU nodes or 1 node with 2 GPUs) to show that a multi-pod job waits until all requested GPUs are available simultaneously.
* **Topology-Aware Scheduling (TAS):** At least 1 multi-GPU node (e.g., 4 or 8 GPUs with NVLink interconnects) to validate KAI's ability to optimize pod placement based on hardware topology to minimize latency.
* **Disaggregated Architectures (Dynamo/Grove):** A multi-node cluster with GPUs is needed to test hierarchical PodGroups and complex distributed serving placement.

## Chart Source

The KAI Scheduler Helm chart is published natively as an OCI artifact. No additional push step is required.

| Field | Value |
|-------|-------|
| Chart OCI URL | `oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler` |

## Dependencies

KAI Scheduler has no hard catalog dependency declared in `requiredDependencies`.

Prerequisites for workload behavior:

- For CPU scheduling tests, no GPU prerequisite is needed.
- For GPU scheduling tests, cluster nodes must expose allocatable accelerator resources (for example, `nvidia.com/gpu` or `amd.com/gpu`).

## Smoke Test Validation

This section captures what was validated and how.

### Key behavior validated

- KAI Scheduler installs as dedicated control-plane components in the `kai-scheduler` namespace.
- Queue resources are created and used for scheduling decisions.
- Workloads are handled by KAI only when they include:

  - `spec.schedulerName: kai-scheduler`
  - `kai.scheduler/queue: default-queue` (or another valid queue).

- CPU workload scheduling path is functional (single pod and parallel Job).
- KAI coexists with the default scheduler for pods that do not select it.
- Invalid queue references leave pods `Pending` with identifiable events.
- GPU scheduling depends on node-level accelerator capacity exposure (for example, `nvidia.com/gpu` or `amd.com/gpu`).

### Installation and verification commands used

```bash
helm upgrade -i kai-scheduler \
  oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler \
  -n kai-scheduler \
  --create-namespace \
  --version <chart-version>

kubectl get pods -n kai-scheduler
kubectl wait --for=condition=Available deployment --all -n kai-scheduler --timeout=180s
kubectl get crd | grep -Ei "kai\\.scheduler|queues|podgroups"
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

### Smoke test procedures

Each numbered workload test below follows the same flow: apply → validate → expected → cleanup.

#### 1. Create test namespace

```bash
kubectl create namespace kai-test --dry-run=client -o yaml | kubectl apply -f -
```

#### 2. Single CPU pod

Validates that a basic CPU pod is scheduled by KAI when it selects `kai-scheduler` and a valid queue.

```bash
kubectl delete pod kai-cpu-smoke -n kai-test --ignore-not-found

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

Validate:

```bash
kubectl get pod kai-cpu-smoke -n kai-test -o wide
kubectl describe pod kai-cpu-smoke -n kai-test
```

Expected:

- Status: `Running`
- Events show `Scheduled` and `Bound` from `kai-scheduler`

Cleanup:

```bash
kubectl delete pod kai-cpu-smoke -n kai-test
```

#### 3. Parallel multi-pod workload

Validates that KAI schedules the pods created by one Kubernetes Job. Multi-pod / batch-style scheduling is one of KAI's supported workload patterns.

```bash
kubectl delete job kai-parallel-cpu -n kai-test --ignore-not-found

kubectl apply -n kai-test -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: kai-parallel-cpu
spec:
  parallelism: 3
  completions: 3
  backoffLimit: 0
  template:
    metadata:
      labels:
        kai.scheduler/queue: default-queue
    spec:
      schedulerName: kai-scheduler
      restartPolicy: Never
      containers:
      - name: worker
        image: registry.k8s.io/pause:3.10
        resources:
          requests:
            cpu: 250m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
EOF
```

Validate:

```bash
kubectl get pods -n kai-test \
  -l job-name=kai-parallel-cpu -o wide

kubectl get events -n kai-test --sort-by=.lastTimestamp \
  | grep kai-parallel-cpu

kubectl get podgroups -A
```

Expected:

- Three pods are created.
- All three are `Running`.
- Events show `Scheduled` and `Bound` from `kai-scheduler`.
- A PodGroup is created for the Job.

Note: because `pause` never exits, the Job stays active until cleaned up.

Cleanup:

```bash
kubectl delete job kai-parallel-cpu -n kai-test
```

#### 4. Scheduler coexistence

Verifies that KAI handles only workloads that explicitly select it. KAI is designed to run alongside the default scheduler.

```bash
kubectl delete pod kai-targeted kai-default -n kai-test \
  --ignore-not-found

kubectl apply -n kai-test -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: kai-targeted
  labels:
    kai.scheduler/queue: default-queue
spec:
  schedulerName: kai-scheduler
  restartPolicy: Never
  containers:
  - name: pause
    image: registry.k8s.io/pause:3.10
---
apiVersion: v1
kind: Pod
metadata:
  name: kai-default
spec:
  restartPolicy: Never
  containers:
  - name: pause
    image: registry.k8s.io/pause:3.10
EOF
```

Validate:

```bash
kubectl get pods kai-targeted kai-default -n kai-test -o wide
kubectl describe pod kai-targeted -n kai-test | grep -E 'Scheduler|Scheduled|Bound'
kubectl describe pod kai-default -n kai-test | grep -E 'Scheduler|Scheduled|Bound'
```

Expected:

- `kai-targeted`: scheduled by `kai-scheduler`
- `kai-default`: scheduled by `default-scheduler`

Cleanup:

```bash
kubectl delete pod kai-targeted kai-default -n kai-test
```

#### 5. Invalid queue test

Validates failure behavior when a workload references a queue that does not exist.

```bash
kubectl delete pod kai-invalid-queue -n kai-test --ignore-not-found

kubectl apply -n kai-test -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: kai-invalid-queue
  labels:
    kai.scheduler/queue: queue-does-not-exist
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

Validate:

```bash
kubectl get pod kai-invalid-queue -n kai-test
kubectl describe pod kai-invalid-queue -n kai-test
kubectl get events -n kai-test --sort-by=.lastTimestamp
```

Expected:

- The pod remains `Pending`.
- Events identify the invalid or unavailable queue.

Cleanup:

```bash
kubectl delete pod kai-invalid-queue -n kai-test
```

#### 6. GPU smoke pod

Requires cluster nodes that expose allocatable GPU capacity (for example, `nvidia.com/gpu`).

```bash
kubectl delete pod kai-gpu-smoke -n kai-test --ignore-not-found

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

Validate:

```bash
kubectl get pod kai-gpu-smoke -n kai-test -o wide
kubectl describe pod kai-gpu-smoke -n kai-test
```

Expected (when GPUs are available):

- Status: `Running` (or `Succeeded` if the sample exits)
- Events show scheduling by `kai-scheduler`

If no GPU capacity is present, the pod stays `Pending` with a scheduler message about missing GPU resources.

Cleanup:

```bash
kubectl delete pod kai-gpu-smoke -n kai-test
```

#### 7. Cleanup test namespace

After all tests:

```bash
kubectl delete namespace kai-test
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

KAI Scheduler installation and queue-based CPU scheduling are validated. GPU scheduling remains blocked by cluster GPU resource exposure/capacity, not by KAI deployment manifests.

## Links

- [GitHub (KAI Scheduler)](https://github.com/kai-scheduler/KAI-Scheduler)
- [Releases](https://github.com/kai-scheduler/KAI-Scheduler/releases)
- [Quickstart](https://github.com/kai-scheduler/KAI-Scheduler/tree/main/docs/quickstart)
