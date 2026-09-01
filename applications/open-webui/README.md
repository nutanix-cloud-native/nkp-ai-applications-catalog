# open-webui

Open WebUI is an extensible, self-hosted web interface for interacting with
large language models.

## Access

Open WebUI does **not** support a URL prefix. In production the UI calls
`/api/config` on the page origin, so `/nkp/open-webui/` cannot work. It is
therefore **not** placed on NKP Traefik (that would take over `/` on the
dashboard host).

The Service is a **LoadBalancer**. After the address is assigned, a post-install
Job writes it to the Launch ConfigMap (`http://<lb-ip>:80/`). Helm
`disableWait` is set so install does not hang if the LB IP is slow.

If the LoadBalancer stays Pending:

```bash
kubectl -n open-webui port-forward svc/open-webui 8080:80
```

Then open `http://127.0.0.1:8080/`.

Open WebUI does **not** declare a catalog dependency on Ollama. Install Ollama
separately if you want a local LLM backend (default values already point at the
catalog Ollama Service).

## Authentication

Open WebUI uses **its own login**. NKP SSO (Traefik Forward Auth / Dex) is not
wired. The first account created in the UI is admin.

## Chart Source

The Open WebUI Helm chart is hosted in a **traditional Helm repository**, not an
OCI registry. It must be pulled locally and pushed to your OCI registry before
the NKP catalog can use it.

Source metadata:

```yaml
helmrepo: open-webui/open-webui
helmrepoUrl: https://helm.openwebui.com/
ocipush: oci://ghcr.io/nutanix-cloud-native/charts/open-webui
```

### How to push the chart to your OCI registry

```bash
# 1. Add the upstream Helm repository
helm repo add open-webui https://helm.openwebui.com/
helm repo update

# 2. Pull the chart version used by this catalog entry
helm pull open-webui/open-webui --version 16.0.0

# 3. Push to your OCI registry
helm push open-webui-16.0.0.tgz oci://ghcr.io/nutanix-cloud-native/charts
```

After pushing, update the OCI URL in `helmrelease/helmrelease.yaml` to match
your registry.

## Icon

The `icon` field in `metadata.yaml` is a base64-encoded PNG. It was generated
from the Open WebUI favicon in the official repository:

| Field | Value |
|-------|-------|
| Source URL | `https://raw.githubusercontent.com/open-webui/open-webui/main/static/favicon.png` |
| Format | PNG (resized to 50x50, base64-encoded) |

To regenerate:

```bash
curl -sL https://raw.githubusercontent.com/open-webui/open-webui/main/static/favicon.png \
  | sips -z 50 50 -o /dev/stdout 2>/dev/null \
  | base64 | tr -d '\n'
```

## Links

- [docs.openwebui.com](https://docs.openwebui.com)
- [GitHub (Open WebUI)](https://github.com/open-webui/open-webui)
- [GitHub (Helm chart)](https://github.com/open-webui/helm-charts)
