# slurm-operator

Kubernetes operator for running and managing Slurm clusters on NKP.

## Chart Source

The Slurm Operator chart is published natively as an OCI artifact.

| Field | Value |
|-------|-------|
| Chart OCI URL | `oci://ghcr.io/slinkyproject/charts/slurm-operator` |
| Version | See the active catalog version directory under `applications/slurm-operator/` |

## Dependencies

| Dependency | Type | Notes |
|------------|------|-------|
| `cert-manager` | hard (`requiredDependencies`) | Required for certificate/issuer resources rendered by the chart |

## Deployment Notes

- The catalog entry deploys the Helm release into a dedicated namespace:
  `slurm-operator`.
- The catalog entry also installs `slurm-operator-crds` first, then deploys the
  main `slurm-operator` chart with a Flux `dependsOn` relationship.
- Default values are provided by `<version>/helmrelease/cm.yaml`.
- Validation overrides are in `<version>/.bloodhound.yaml` for cert-manager
  resource kinds.

## E2E Smoke Test Validation

Use this flow to validate end-to-end functionality with an already deployed
`slurm-operator` instance on the NKP cluster through Kommander. This smoke test does not reinstall the operator; it
creates a temporary Slurm workload namespace, verifies scheduling works, then
cleans up all temporary resources.

Set kubeconfig:

```sh
export KUBECONFIG=/path/to/workload-cluster.conf
```

Preflight checks for the deployed slurm-operator:

```sh
kubectl get pods -n slurm-operator
kubectl get certificate,issuer -n slurm-operator
kubectl api-resources --api-group=slinky.slurm.net
```

Create temporary smoke workload (reconciled by the existing operator):

```sh
kubectl create namespace slurm-smoke
helm upgrade --install slurm-smoke oci://ghcr.io/slinkyproject/charts/slurm \
  --version 1.1.1 \
  --namespace slurm-smoke \
  --set controller.persistence.enabled=false \
  --set nodesets.slinky.replicas=1 \
  --wait --timeout 12m
kubectl wait --for=condition=Ready pod -n slurm-smoke --all --timeout=8m
```

Validate Slurm scheduling path from the controller pod:
- `sinfo` verifies Slurm sees the partition and worker node.
- `srun` verifies an interactive job can be placed and executed immediately.
- `sbatch` verifies batch submission/queueing/completion metadata.

```sh
# 1) Cluster view from Slurm (partitions + node state)
kubectl exec -n slurm-smoke slurm-smoke-controller-0 -- sinfo

# 2) Immediate scheduling check (should print worker hostname)
kubectl exec -n slurm-smoke slurm-smoke-controller-0 -- srun -N1 -n1 hostname

# 3) Batch job check with detailed status
kubectl exec -n slurm-smoke slurm-smoke-controller-0 -- sh -lc \
  'JOBID=$(sbatch --parsable --wrap="hostname"); echo JOBID=$JOBID; \
   squeue -j "$JOBID" || true; \
   scontrol show job "$JOBID"; \
   sacct -j "$JOBID" --format=JobID,State,ExitCode -n || true'
```

Expected result:
- `sinfo` shows a schedulable node (for example `slinky-0`).
- `srun` returns a worker hostname.
- `scontrol show job` reports `JobState=COMPLETED` and `ExitCode=0:0`.
- `squeue` may show the job briefly in queue/running states before completion.
- `sacct` may print `Slurm accounting storage is disabled` in minimal smoke setups; this is expected when accounting is not configured.

Cleanup:

```sh
helm uninstall slurm-smoke -n slurm-smoke
kubectl delete namespace slurm-smoke
kubectl get controllers,nodesets,loginsets,restapis -A
kubectl get pods -n slurm-operator
```

## Links

- [Slinky Project](https://slinky.ai/)
- [GitHub](https://github.com/SlinkyProject/slurm-operator)
- [Installation guide](https://slinky.schedmd.com/projects/slurm-operator/en/main/installation.html)
