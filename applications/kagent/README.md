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

The catalog defaults include:

- `fullnameOverride: "kagent"` to keep resource names stable (`kagent-*`) so
  Agent/RemoteMCPServer references resolve consistently.
- `registry: "ghcr.io"` because the chart defaults its images to
  `cr.kagent.dev`, which no longer serves the `0.7.13` controller/ui/app images.
  Those images are published to `ghcr.io/kagent-dev/kagent/*`, so we pin the
  registry there. (NKP Flux disables chart digest tracking, so the image tag
  resolves to a clean `0.7.13` with no `+<digest>` suffix and needs no override.)

## Dashboard (Launch button)

This catalog does **not** include a Traefik IngressRoute or Middleware. The kagent UI is exposed via a **LoadBalancer** service
(`ui.service.type: LoadBalancer` in the default values).

- **Launch URL:** A post-install Job discovers the **kagent-ui** LoadBalancer
  external IP in the `kagent` namespace and patches the `kagent-ui` ConfigMap
  with `dashboardLink` (e.g. `http://<lb-ip>:8080/`). The NKP Launch button
  uses that URL.
- **In-cluster (no LoadBalancer):** If you override to ClusterIP, use
  `http://kagent-ui.kagent.svc.cluster.local:8080` or
  `kubectl port-forward -n kagent svc/kagent-ui 8080:8080` and open
  http://localhost:8080.

## Dependencies

| Dependency | Type | Notes |
|------------|------|-------|
| `ollama` | soft (`dependencies`) | Recommended LLM backend; not required if using a cloud provider |

## Observability agent

The **observability-agent** (Prometheus/Grafana/Kubernetes monitoring) is enabled
in the catalog defaults (`agents.observability-agent.enabled: true`). If it shows
**unavailable** in the UI at `/agents/new?name=observability-agent&...`, either the
agent deployment was not created (upgrade the Helm release with the catalog values)
or its tools cannot reach Grafana/Prometheus. The agent expects Grafana at
`grafana-mcp.grafana.url` (default: `grafana.kagent:3000/api`). Install Grafana (and
optionally Prometheus) in the cluster or point `grafana-mcp.grafana.url` to an
existing instance for the agent to become available.

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
