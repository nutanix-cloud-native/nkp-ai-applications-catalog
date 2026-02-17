# weaviate

Open-source vector database for AI-powered search and applications.

## Chart Source

The Weaviate Helm chart is hosted in a **traditional Helm repository**, not an
OCI registry. It must be pulled locally and pushed to your OCI registry before
the NKP catalog can use it.

Source metadata is stored in `.catalog-source.yaml`:

```yaml
helmrepo: weaviate/weaviate
helmrepoUrl: https://weaviate.github.io/weaviate-helm/
ocipush: oci://ghcr.io/nutanix-cloud-native/weaviate-helm/weaviate
```

### How to push the chart to your OCI registry

```bash
# 1. Add the upstream Helm repository
helm repo add weaviate https://weaviate.github.io/weaviate-helm/
helm repo update

# 2. Pull the chart version used by this catalog entry
helm pull weaviate/weaviate --version 17.7.0

# 3. Push to your OCI registry
helm push weaviate-17.7.0.tgz oci://<your-oci-registry>/weaviate-helm/weaviate
```

After pushing, update the OCI URL in `helmrelease/helmrelease.yaml` and
`.catalog-source.yaml` to match your registry.

## Icon

The `icon` field in `metadata.yaml` is a base64-encoded SVG. It was generated
from the Weaviate icon in the official website repository:

| Field | Value |
|-------|-------|
| Source URL | `https://raw.githubusercontent.com/weaviate/weaviate-io/main/static/img/site/build-weaviate-icon.svg` |
| Format | SVG (base64-encoded) |

To regenerate:

```bash
curl -sL https://raw.githubusercontent.com/weaviate/weaviate-io/main/static/img/site/build-weaviate-icon.svg | base64 | tr -d '\n'
```

## Links

- [weaviate.io](https://weaviate.io)
- [GitHub (Weaviate)](https://github.com/weaviate/weaviate)
- [GitHub (Helm chart)](https://github.com/weaviate/weaviate-helm)
