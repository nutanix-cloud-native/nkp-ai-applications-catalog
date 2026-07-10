# agentgateway

AI-focused Kubernetes gateway for security, observability, and traffic
management of LLM workloads.

## Chart Source

The agentgateway Helm chart is published natively as an OCI artifact. No
additional push step is required.

| Field | Value |
|-------|-------|
| Chart OCI URL | `oci://cr.agentgateway.dev/charts/agentgateway` |
| CRDs Chart OCI URL | `oci://cr.agentgateway.dev/charts/agentgateway-crds` |
| Version | `v2.2.0` |

## Dependencies

| Dependency | Type | Notes |
|------------|------|-------|
| `gateway-api-crds` | hard (`requiredDependencies`) | NKP platform app; must be deployed first |

## Icon

The `icon` field in `metadata.yaml` is a base64-encoded SVG. It was generated
from the agentgateway favicon in the official website repository:

| Field | Value |
|-------|-------|
| Source URL | `https://raw.githubusercontent.com/agentgateway/website/refs/heads/main/static/favicon.svg` |
| Format | SVG (base64-encoded) |

To regenerate:

```bash
curl -sL https://raw.githubusercontent.com/agentgateway/website/refs/heads/main/static/favicon.svg | base64 | tr -d '\n'
```

## Links

- [agentgateway.dev](https://agentgateway.dev)
- [Helm install guide](https://kgateway.dev/docs/agentgateway/main/install/helm)
