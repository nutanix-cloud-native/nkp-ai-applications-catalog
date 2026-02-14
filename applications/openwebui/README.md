# openwebui

Extensible, self-hosted web interface for interacting with large language models.

## Chart Source

The Open WebUI Helm chart is hosted in a **traditional Helm repository**, not an
OCI registry. It must be pulled locally and pushed to your OCI registry before
the NKP catalog can use it.

Source metadata is stored in `.catalog-source.yaml`:

```yaml
helmrepo: open-webui/open-webui
helmrepoUrl: https://helm.openwebui.com/
ocipush: oci://<your-oci-registry>/open-webui
```

### How to push the chart to your OCI registry

```bash
# 1. Add the upstream Helm repository
helm repo add open-webui https://helm.openwebui.com/
helm repo update

# 2. Pull the chart version used by this catalog entry
helm pull open-webui/open-webui --version 12.0.1

# 3. Push to your OCI registry
helm push open-webui-12.0.1.tgz oci://<your-oci-registry>/open-webui
```

After pushing, update the OCI URL in `helmrelease/helmrelease.yaml` and
`.catalog-source.yaml` to match your registry.

## Dependencies

| Dependency | Type | Notes |
|------------|------|-------|
| `ollama` | soft (`dependencies`) | Recommended LLM backend |
| `vllm` | soft (`dependencies`) | Alternative LLM backend |

## Icon

The `icon` field in `metadata.yaml` is a base64-encoded SVG. It was generated
from the Open WebUI favicon in the official repository:

| Field | Value |
|-------|-------|
| Source URL | `https://raw.githubusercontent.com/open-webui/open-webui/4269df041fef62208d59babe0faae866d2bfbc3c/static/favicon/favicon.svg` |
| Format | SVG (base64-encoded) |

To regenerate:

```bash
curl -sL https://raw.githubusercontent.com/open-webui/open-webui/4269df041fef62208d59babe0faae866d2bfbc3c/static/favicon/favicon.svg | base64 | tr -d '\n'
```

## Links

- [docs.openwebui.com](https://docs.openwebui.com)
- [GitHub (Open WebUI)](https://github.com/open-webui/open-webui)
- [GitHub (Helm chart)](https://github.com/open-webui/helm-charts)
