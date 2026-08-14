# vllm

High-throughput LLM serving engine for production inference.

## Chart Source

The vLLM Helm chart is hosted in a **traditional Helm repository**, not an
OCI registry. It must be pulled locally and pushed to your OCI registry before
the NKP catalog can use it.

Source metadata is stored in `.catalog-source.yaml`:

```yaml
helmrepo: vllm/vllm
helmrepoUrl: https://open-source-ai-dev.github.io/vllm-helm-chart
ocipush: oci://<your-oci-registry>/vllm
```

### How to push the chart to your OCI registry

```bash
# 1. Add the upstream Helm repository
helm repo add vllm https://open-source-ai-dev.github.io/vllm-helm-chart
helm repo update

# 2. Pull the chart version used by this catalog entry
helm pull vllm/vllm --version 0.1.1

# 3. Push to your OCI registry
helm push vllm-0.1.1.tgz oci://<your-oci-registry>/vllm
```

After pushing, update the OCI URL in `helmrelease/helmrelease.yaml` and
`.catalog-source.yaml` to match your registry.

## Icon

The `icon` field in `metadata.yaml` is a base64-encoded SVG. It was generated
from the vLLM logo in the official media kit repository:

| Field | Value |
|-------|-------|
| Source URL | `https://raw.githubusercontent.com/vllm-project/media-kit/main/vLLM-Logo.svg` |
| Format | SVG (base64-encoded) |

To regenerate:

```bash
curl -sL https://raw.githubusercontent.com/vllm-project/media-kit/main/vLLM-Logo.svg | base64 | tr -d '\n'
```

## Links

- [vllm.ai](https://docs.vllm.ai)
- [GitHub (vLLM)](https://github.com/vllm-project/vllm)
- [GitHub (Helm chart)](https://github.com/open-source-ai-dev/vllm-helm-chart)
