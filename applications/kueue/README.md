# kueue

Kubernetes-native job queueing with quota management and all-or-nothing (gang)
admission for batch and AI/ML workloads.

## Table of Contents

**Setup and usage**

- [Chart Source](#chart-source)
- [Default Configuration](#default-configuration)
- [Getting Started (hello world)](#getting-started-hello-world)
- [GPU queueing](#gpu-queueing)
- [Dependencies](#dependencies)

**Concepts and FAQ**

- [Introduction](#introduction)
- [Foundational concepts](#foundational-concepts)
- [What Kueue solves](#what-kueue-solves)
- [Testing and validation](#testing-and-validation)
- [FAQ](#faq)
- [For administrators](#for-administrators)
- [Links](#links)

## Chart Source


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

## Introduction

Kueue is a job queueing and quota system for batch and AI/ML workloads.

> **ELI5:** Kueue is the host at a busy restaurant. It just decides when your party is allowed in, so the kitchen never gets slammed and every group gets a fair turn.

**The problem it solves.** On a shared cluster, especially an expensive GPU cluster, the default Kubernetes scheduler can cause problems. When many teams submit large training/batch jobs, three things happen:

- **Resource deadlock:** a multi-pod job gets half its pods running, then waits forever for the rest while holding those resources hostage.
- **Starvation / no fairness:** one team's flood of jobs can hog the whole cluster; Kubernetes has no built-in per-team quota.
- **No real queue:** a pod is either schedulable right now or stuck `Pending`, with no ordering or policy about whose turn it is.

> **ELI5:** Imagine 4 friends want a table but only 2 seats are open. Plain Kubernetes seats 2 of them and makes them wait while the other 2 stand around blocking the aisle, nobody can eat, and the seats are wasted.

**What Kueue adds.** Kueue sits above the scheduler as an admission gate. Instead of "where does this pod go?", it asks "should this whole job be allowed to start yet?", based on quotas per team/queue.

- **All-or-nothing (gang) admission:** a job starts only when all its pods can run, so there is no partial-allocation deadlock.

**Key distinction:** Kueue does not replace the Kubernetes scheduler. It holds jobs in a queue (suspended) until quota and policy allow, then hands the admitted job to the normal scheduler to place.

> **ELI5:** The host (Kueue) decides when your party is seated; the waiter (kube-scheduler) still decides which table.

**Concrete example.** A team submits a 4-pod training job needing 4 GPUs, but only 2 are free:

- **Without Kueue:** Kubernetes runs 2 pods, the job hangs half-alive, and 2 GPUs sit wasted.
- **With Kueue:** the job waits in the queue until all 4 GPUs are free, then is admitted all at once.

## Foundational concepts

Kueue's data model centers on five core objects (CRDs). It installs more CRDs
than these (for example `AdmissionCheck`, `Topology`, MultiKueue types), but
these five are what you interact with day to day:

| Object | What it is | ELI5 |
|--------|-----------|------|
| **ResourceFlavor** | A named "type" of resource, usually mapped to a kind of node (for example spot CPU nodes, A100 GPU nodes, H100 GPU nodes). Lets quota distinguish between different hardware. | the different kinds of tables (booths, patio, bar) |
| **ClusterQueue** | A cluster-wide pool of quota. Says how much of each resource (`cpu`, `memory`, `nvidia.com/gpu`) is available for a given flavor. Cluster-scoped. Can hold separate buckets per flavor (for example "4 A100" and "2 H100", not just "6 GPUs"). | the seating capacity a section is promised |
| **LocalQueue** | A namespaced pointer to a `ClusterQueue`. What users submit to, and how a team/namespace gets a slice of cluster quota. | the waitlist clipboard for your party |
| **Workload** | Auto-created by Kueue to represent one job waiting for admission. You do not create it directly; Kueue makes it when you submit a Job (or other supported kind) carrying a queue-name label. Its status shows whether it is `Admitted`. | your name written on the waitlist |
| **Cohort** | An optional group of `ClusterQueue`s that can borrow each other's unused quota. | neighboring sections that lend each other empty tables |

**How they fit together.** A user submits a Job labeled with a `LocalQueue` name. Kueue creates a `Workload` for it, looks up the `LocalQueue` (which points at a `ClusterQueue`), checks whether that `ClusterQueue`'s quota for the requested `ResourceFlavor` can fit the whole job, and borrows from the `Cohort` if needed. If it fits, the job is admitted and unsuspended; if not, it waits in the queue.

## What Kueue solves

- **Gang admission (no half-running jobs):** a distributed training job needs all its workers at once. Kueue only admits it when the whole set fits, so you never get a job stuck with half its pods running and the rest pending.
- **Quota and multi-tenancy:** each team gets a `ClusterQueue` with defined limits, so one team cannot consume the entire cluster.
- **Queueing and ordering:** when capacity is full, jobs wait in an actual queue with priorities.
- **Borrowing and higher utilization:** through `Cohort`s, a team can temporarily use another team's idle quota, then give it back when the owner needs it. This keeps expensive hardware busy instead of idle.
- **Preemption:** higher priority work can reclaim capacity from lower priority work when needed, so urgent jobs are not blocked behind low priority ones.
- **GPU-aware quota:** because resources are tracked per `ResourceFlavor`, all of the above works for GPUs specifically (for example "4 A100s for team A"), not just generic CPU and memory. This is the main reason Kueue matters for AI/ML.

**Net:** Kueue turns a first-come greedy free-for-all into a fair, policy-driven queue that keeps expensive hardware busy and prevents deadlock.

## Testing and validation

### How much testing can be done on CPU-only clusters?

**More than 90%.** Kueue's logic is resource-agnostic. It makes admission decisions on abstract resource quantities (`cpu`, `memory`, or any countable resource name), so the entire policy engine can be exercised with tiny CPU/memory jobs.

Even GPU quota logic is testable without GPUs. A `ClusterQueue`'s quota is a number you define, and Kueue admits based on its own accounting, not on real hardware. So you can declare `nvidia.com/gpu` quota, submit jobs that request it, and watch Kueue admit or queue them exactly as it would with real cards. The catch: once admitted, the pod will not actually run (the scheduler finds no GPU node, so the pod stays `Pending`).

**What you cannot test on CPU-only (needs real GPUs):**

- An admitted GPU pod actually scheduling and running on a GPU node (on CPU-only it stays `Pending` after admission).
- Real GPU execution and the NVIDIA device plugin advertising `nvidia.com/gpu`.

Note: the quota decision, including per-flavor quota (A100 vs H100), is testable CPU-only. Only the physical landing and execution need real GPUs.

### How many GPU nodes, and of what types?

It depends on which GPU behavior you want to prove. Kueue itself is hardware-agnostic, so the GPU model does not matter for correctness. Any NVIDIA GPU the device plugin can advertise as `nvidia.com/gpu` is enough.

| Goal | Minimum hardware |
|------|------------------|
| A single GPU job is admitted and actually runs | 1 GPU (one node, one GPU) |
| Gang / all-or-nothing and quota contention with real GPUs | 2 GPUs (one 2-GPU node, or two 1-GPU nodes): show "job needs 2, only 1 free, it waits, then runs when freed" |
| Borrowing and preemption across two teams | 4 GPUs (split 2 and 2 between two `ClusterQueue`s) |
| Per-flavor placement across GPU models (A100 vs H100) | at least one node of each model, labeled per flavor |

## FAQ

**Q: How does a `ClusterQueue` map its quota (for example 4 cpu) to actual nodes?**
A: It does not map to specific nodes at all. The `4 cpu` is a logical budget inside Kueue, not a reservation on any node. There are two independent layers:

- **Layer 1, Kueue quota accounting (no node awareness):** `nominalQuota` is just a number Kueue tracks. When you submit jobs, Kueue sums the cpu requests of everything it has admitted and stops admitting once the total would pass 4. It never looks at nodes for this.
- **Layer 2, real scheduling onto nodes (after admission):** once Kueue admits a job, it unsuspends it and hands the pods to kube-scheduler, which finds real nodes with free cpu, exactly as normal.

The only link between quota and real nodes is the `ResourceFlavor`. A flavor can carry `nodeLabels` (for example `instance-type: gpu-a100`); when Kueue admits against that flavor, it injects those labels as a `nodeSelector` so the scheduler only places pods on matching nodes. The `default-flavor` has no `nodeLabels`, so it matches any node.

> **ELI5:** the "4 cpu" is the number written in the section's reservation book, not the chairs themselves. The `ResourceFlavor` is which part of the restaurant that book covers. The real chairs still have to exist, and it is the manager's job to make the book match the real chair count.

**Q: Does Kueue replace the Kubernetes scheduler?**
A: No. Kueue is an admission gate that decides when a job is allowed to start. Once it admits a job, the normal kube-scheduler still decides which node.

**Q: Is quota tied to real node capacity?**
A: No. `nominalQuota` is a logical budget Kueue tracks itself; it does not read node capacity. The admin is responsible for setting quota to match real hardware and for pointing `ResourceFlavor`s at the right nodes via labels.

**Q: What happens if I set quota higher than real capacity?**
A: Kueue over-admits. It grants the budget, the jobs unsuspend, then the pods sit `Pending` because no real node can place them. Kueue thinks there is room; Kubernetes cannot deliver it.

**Q: My job was admitted but the pod is stuck `Pending`. Is Kueue broken?**
A: No. Admission and placement are two layers. Kueue admitted it (quota was fine), but kube-scheduler found no node with enough free resources. That is a cluster capacity issue, not a Kueue issue.

**Q: Does Kueue need GPUs?**
A: No. Kueue is resource-agnostic. The entire policy engine (quotas, gang, borrowing, preemption) works on CPU. GPUs are just another countable resource it can manage.

**Q: How does a job become managed by Kueue?**
A: It must carry the `kueue.x-k8s.io/queue-name` label pointing at a `LocalQueue`. A job without that label runs normally and is not gated by Kueue.

**Q: What workload types does it support?**
A: `batch/Job`, `JobSet`, Ray (`RayJob`/`RayService`/`RayCluster`), and the Kubeflow training jobs (PyTorch, TF, MPI, XGBoost, JAX, PaddlePaddle, TrainJob) are enabled by default in this chart. Plain Pods, Deployments, and StatefulSets are supported but require enabling their integration. Any non-core integration also needs the matching CRD/controller present on the cluster.

**Q: Difference between `ClusterQueue` and `LocalQueue`?**
A: `ClusterQueue` holds the actual quota and policy and is cluster-scoped. `LocalQueue` is a namespaced pointer to a `ClusterQueue` and is what users submit to. That is how a namespace gets a slice of cluster quota.

**Q: Can one team use another team's idle capacity?**
A: Yes, through `Cohort`s. `ClusterQueue`s in the same cohort can borrow each other's unused quota and give it back when the owner needs it.

## For administrators

The administrator installs Kueue, defines the quota model, and sets the rules teams operate under. Users just submit jobs; admins decide how much each team gets and what happens under contention. This maps closely to the upstream [Manage tasks](https://kueue.sigs.k8s.io/docs/tasks/manage/).

> **ELI5:** the admin is the restaurant manager who sets how many tables exist, which sections each party can use, and the seating rules. The user is just a diner who shows up and asks for a table.

**Q: After installing Kueue from the catalog, what does an admin set up?**
A: Kueue installs with no queues, on purpose. The admin creates the quota model in three layers:

1. **`ResourceFlavor`:** describes a kind of hardware (for example cpu-only, or A100 GPU nodes), optionally pinned to nodes via `nodeLabels`.
2. **`ClusterQueue`:** the cluster-wide budget. Says how much `cpu`/`memory`/`nvidia.com/gpu` may be admitted, against which flavors, and the contention rules.
3. **`LocalQueue`:** a namespaced pointer to a `ClusterQueue` that teams submit against.

Admins own `ResourceFlavor` and `ClusterQueue` (cluster-scoped); teams get a `LocalQueue` in their namespace.

**Q: How does RBAC split between admins and users?**
A: The split follows resource scope:

- **Admins (cluster role):** create/edit `ResourceFlavor`, `ClusterQueue`, `Cohort`, `AdmissionCheck`, and Kueue config. These are cluster-scoped and decide fairness and capacity, so they should be locked down.
- **Users (namespaced role):** create a `LocalQueue` in their own namespace (or just consume one the admin created) and submit jobs carrying the `kueue.x-k8s.io/queue-name` label.

A common policy: admins pre-create the `LocalQueue` per team namespace, and users only get permission to create Jobs, not queues. That stops a team from inventing its own queue to bypass quota.

**Q: On NKP specifically, how does this map to workspaces and projects?**
A: NKP workspaces and projects are backed by namespaces. The clean model: the platform admin owns `ClusterQueue`s and flavors at the cluster level, then drops one `LocalQueue` into each workspace/project namespace. Each tenant submits to its own `LocalQueue`, and the shared `ClusterQueue` (or a `Cohort` of them) is where fairness between tenants is enforced.

**Q: What policies can an admin enforce beyond raw quota?**
A:

- **Borrowing:** let a queue temporarily use another queue's idle quota within the same `Cohort`, with an optional `borrowingLimit`.
- **Lending limits:** cap how much of its own quota a queue is willing to lend out.
- **Preemption:** allow a higher-priority or under-its-quota workload to evict an admitted one. Configurable within a queue and across the cohort.
- **Fair sharing:** weight how spare capacity is split between competing teams, instead of first-come-first-served.

**Q: How does an admin guarantee gang admission actually holds (no half-started jobs)?**
A: Two layers. Kueue's admission already reserves the full quota for a workload before it starts (all-or-nothing on quota). To also guarantee all pods become Ready together, the admin enables `waitForPodsReady` in the Kueue config. That makes Kueue wait for the whole pod group to be schedulable and roll back/requeue if it stalls, which prevents one job from holding GPUs hostage while waiting for the rest.

**Q: What are AdmissionChecks and ProvisioningRequest, and when does an admin care?**
A: They are extra gates an admin can attach to a `ClusterQueue` so a workload is admitted only after an external condition is met. The most common is `ProvisioningRequest`: do not admit the GPU job until the cluster autoscaler confirms it can actually provision the GPU nodes. This matters on elastic/cloud clusters where capacity is created on demand; on a fixed on-prem cluster it is usually optional.

**Q: How does an admin change quota or observe what Kueue is doing?**
A: Quotas are just fields on the `ClusterQueue`, so an admin edits `nominalQuota` and Kueue applies it live (newly submitted work respects the new numbers). For visibility, watch the `ClusterQueue` status (`admittedWorkloads`, `pendingWorkloads`, flavor usage) and Kueue's Prometheus metrics. That is how an admin answers "who is waiting, who is over their share, and is any quota sitting idle."

## Links

- [Kueue docs](https://kueue.sigs.k8s.io/docs/)
- [GitHub](https://github.com/kubernetes-sigs/kueue)
- [Helm chart reference](https://github.com/kubernetes-sigs/kueue/blob/main/charts/kueue/README.md)
