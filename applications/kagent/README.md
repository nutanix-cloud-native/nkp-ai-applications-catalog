# kagent

Kubernetes-native AI agent framework built on Microsoft AutoGen.

## Chart Source

The kagent Helm chart is published natively as an OCI artifact. No additional
push step is required.

| Field | Value |
|-------|-------|
| Chart OCI URL | `oci://ghcr.io/kagent-dev/kagent/helm/kagent` |
| CRDs Chart OCI URL | `oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds` |
| Version | `0.7.13` |

## Default Configuration

The default Helm values configure Ollama as the LLM provider
(`providers.default=ollama`). The Ollama host is set to the in-cluster
service at `ollama.${releaseNamespace}.svc.cluster.local:11434`.

To use a different provider, override the values via the NKP app
configuration UI or update `helmrelease/cm.yaml`.

## Dashboard and SSO (Launch button)

- **Traefik + forward-auth (recommended for SSO):** This catalog exposes the
  kagent UI via Traefik with a forward-auth middleware so the NKP Launch
  button opens a URL that goes through **traefik-forward-auth** (SSO). A
  post-install Job discovers the Traefik LoadBalancer and patches the
  `kagent-ui` ConfigMap with `dashboardLink` (e.g. `https://<traefik-lb>/kagent/`).
  Requires Traefik and **traefik-forward-auth** running in the cluster (e.g.
  service `traefik-forward-auth` in namespace `traefik` on port 4181). If your
  Traefik service or namespace differ, set env in the Job or adjust the RBAC
  and Job script.
- **Plain service URL (no SSO):** In-cluster only:
  `http://<releaseName>-ui.<releaseNamespace>.svc.cluster.local:8080`. Use
  `kubectl port-forward -n <ns> svc/<releaseName>-ui 8080:8080` and open
  http://localhost:8080; no SSO.

## Dependencies

| Dependency | Type | Notes |
|------------|------|-------|
| `ollama` | soft (`dependencies`) | Recommended LLM backend; not required if using a cloud provider |

## Icon

The `icon` field in `metadata.yaml` is a base64-encoded SVG. It was generated
from the kagent logo in the official repository:

| Field | Value |
|-------|-------|
| Source URL | `https://raw.githubusercontent.com/kagent-dev/kagent/main/img/icon-light.svg` |
| Format | SVG (base64-encoded) |

To regenerate:

```bash
curl -sL https://raw.githubusercontent.com/kagent-dev/kagent/main/img/icon-light.svg | base64 | tr -d '\n'
```

## Links

- [kagent.dev](https://kagent.dev)
- [GitHub](https://github.com/kagent-dev/kagent)
- [Helm chart reference](https://kagent.dev/docs/kagent/resources/helm)
