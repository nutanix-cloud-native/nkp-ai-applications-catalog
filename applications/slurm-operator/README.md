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

## Links

- [Slinky Project](https://slinky.ai/)
- [GitHub](https://github.com/SlinkyProject/slurm-operator)
- [Installation guide](https://slinky.schedmd.com/projects/slurm-operator/en/main/installation.html)
