# slurm-operator

Kubernetes operator for running and managing Slurm clusters on NKP.

## Catalog Versions

| Catalog version | Upstream chart |
|-----------------|----------------|
| `1.1.1` | `slurm-operator` `1.1.1` |

## Chart Source

The Slurm Operator chart is published natively as an OCI artifact.

| Field | Value |
|-------|-------|
| Chart OCI URL | `oci://ghcr.io/slinkyproject/charts/slurm-operator` |
| Version | `1.1.1` |

## Dependencies

| Dependency | Type | Notes |
|------------|------|-------|
| `cert-manager` | hard (`requiredDependencies`) | Required for certificate/issuer resources rendered by the chart |

## Deployment Notes

- The catalog entry deploys the Helm release into a dedicated namespace:
  `slurm-operator`.
- Default values are provided by `1.1.1/helmrelease/cm.yaml`.
- Validation overrides are in `1.1.1/.bloodhound.yaml` for cert-manager
  resource kinds.

## Links

- [Slinky Project](https://slinky.ai/)
- [GitHub](https://github.com/SlinkyProject/slurm-operator)
- [Installation guide](https://slinky.schedmd.com/projects/slurm-operator/en/main/installation.html)
