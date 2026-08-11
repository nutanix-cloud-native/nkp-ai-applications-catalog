# kagent

Kubernetes-native AI agent framework for declarative agent lifecycle management.

## Chart Source

The kagent Helm chart is published natively as an OCI artifact.

| Field | Value |
|-------|-------|
| Chart OCI URL | `oci://ghcr.io/kagent-dev/kagent/helm/kagent` |
| CRDs Chart OCI URL | `oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds` |
| Version | `0.9.12` |

## Default Configuration

The catalog defaults include:

- `fullnameOverride: "kagent"` to keep resource names stable (`kagent-*`).
- `registry: "ghcr.io"` because chart defaults point at `cr.kagent.dev`, while
  this catalog pins to tags verified in `ghcr.io/kagent-dev/kagent/*` (for
  example `ghcr.io/kagent-dev/kagent/ui:0.9.12`).
- `ui.service.type: ClusterIP` to avoid creating billable cloud load balancers by default.
- `database.postgres.bundled.enabled: true` for quickstart installs.
- `providers.default=ollama` with host
  `ollama-ollama.ollama.svc.cluster.local:11434`.
- `providers.ollama.config.options.num_ctx: "64000"` is carried explicitly
  because overriding `providers.ollama.config` replaces the full map.

### PostgreSQL caveat

kagent 0.8+ uses PostgreSQL as the only backend. Upstream documents the bundled
PostgreSQL as development/evaluation only. For production, set
`database.postgres.url` to an external database.

### UI access

This catalog entry does not create path-based routing or dashboard launch links.
This is a current product constraint, not a temporary omission:

- kagent's UI is a Next.js build that emits root-relative URLs and does not
  support running under a base path like `/nkp/kagent/`.
- A hostname-based route would work, but it requires per-customer DNS and TLS
  certificates, which a catalog entry cannot assume.
- When upstream base-path support lands, this entry can add ingress + auth
  middleware and a dashboard launch link.

Access the UI with port-forward:

```bash
kubectl port-forward -n kagent svc/kagent-ui 8080:8080
```

Then open `http://localhost:8080`.

### `ui.publicBackendUrl` note

Do not override `ui.publicBackendUrl` in chart values for this catalog entry.
In this kagent version, that value is inlined into the client bundle at build
time, and the runtime container startup does not rewrite it from env vars.
An override appears in pod/deployment environment but silently has no effect:
the browser still uses the compiled default. The chart default `"/api"` is the
correct value.

## Dependencies

| Dependency | Type | Notes |
|------------|------|-------|
| `ollama` | soft (`dependencies`) | Recommended LLM backend; app can use another configured provider |

## Observability agent

`observability-agent.enabled` is set in defaults. If it appears unavailable in
the UI, verify the deployment exists and that Grafana/Prometheus endpoints are
reachable by the related tools.

## Icon

The `icon` field in `metadata.yaml` is base64-encoded. To regenerate:

```bash
curl -sL https://raw.githubusercontent.com/kagent-dev/kagent/main/img/icon-light.svg | base64 | tr -d '\n'
```

## Links

- [kagent.dev](https://kagent.dev)
- [GitHub](https://github.com/kagent-dev/kagent)
- [Helm chart reference](https://kagent.dev/docs/kagent/resources/helm)
