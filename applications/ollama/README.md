# ollama

Lightweight LLM runtime with an OpenAI-compatible API.

## Chart Source

The ollama Helm chart is hosted in a **traditional Helm repository**, not an
OCI registry. It must be pulled locally and pushed to your OCI registry before
the NKP catalog can use it.

Source metadata is stored in `.catalog-source.yaml`:

```yaml
helmrepo: ollama-helm/ollama
helmrepoUrl: https://otwld.github.io/ollama-helm/
ocipush: oci://<your-oci-registry>/ollama-helm/ollama
```

### How to push the chart to your OCI registry

```bash
# 1. Add the upstream Helm repository
helm repo add ollama-helm https://otwld.github.io/ollama-helm/
helm repo update

# 2. Pull the chart version used by this catalog entry
helm pull ollama-helm/ollama --version 1.39.0

# 3. Push to your OCI registry
helm push ollama-1.39.0.tgz oci://<your-oci-registry>/ollama-helm/ollama
```

After pushing, update the OCI URL in `helmrelease/helmrelease.yaml` and
`.catalog-source.yaml` to match your registry.

## Default Configuration

The default Helm values (`helmrelease/cm.yaml`) auto-pull the `llama3.2`
model on startup and enable a 30Gi persistent volume for model storage.

### In-cluster endpoint

The chart creates the service `ollama-ollama` in namespace `ollama`.
Use this endpoint from other in-cluster apps:

`http://ollama-ollama.ollama.svc.cluster.local:11434`

## Icon

The `icon` field in `metadata.yaml` is a base64-encoded SVG. It was generated
from the Ollama favicon in the official repository:

| Field | Value |
|-------|-------|
| Source URL | `https://raw.githubusercontent.com/ollama/ollama/main/docs/favicon.svg` |
| Format | SVG (base64-encoded) |

To regenerate:

```bash
curl -sL https://raw.githubusercontent.com/ollama/ollama/main/docs/favicon.svg | base64 | tr -d '\n'
```

## Links

- [ollama.com](https://ollama.com)
- [GitHub (ollama)](https://github.com/ollama/ollama)
- [GitHub (Helm chart)](https://github.com/otwld/ollama-helm)
