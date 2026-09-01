# open-webui

Open WebUI is an extensible, self-hosted web interface for interacting with
large language models.

## Access

Open WebUI cannot use NKP SSO because it has no URL prefix: the production UI
hard-codes `WEBUI_BASE_URL` to empty, so the browser always calls `/api/config`
(and other assets) at the page origin root. NKP SSO is Traefik Forward Auth on
the **same origin** as the NKP dashboard (often a raw Traefik IP). A path such
as `/nkp/open-webui/` therefore cannot work: after login the SPA still requests
`/api/config` on the NKP host, which is not Open WebUI. A second hostname
(sslip.io or `/etc/hosts`) also fails, because Forward Auth’s `authHost` is the
Traefik address and the browser is sent there, where `/` is not Open WebUI.
Serving Open WebUI as Traefik’s catch-all at `/` on that origin *would* make
SSO work, but it would take over the NKP UI’s root. nginx rewrite or
`sub_filter` cannot fix this either: production JS still issues root-relative
fetches.

Open WebUI is therefore exposed on its **own** LoadBalancer at `/`. After the
address is assigned, a post-install Job writes it to the Launch ConfigMap
(`http://<lb-ip>:80/`). Helm `disableWait` is set so install does not hang if
the LB IP is slow.

If the LoadBalancer stays Pending:

```bash
kubectl -n open-webui port-forward svc/open-webui 8080:80
```

Then open `http://127.0.0.1:8080/`.

Open WebUI does **not** declare a catalog dependency on Ollama. Install Ollama
separately if you want a local LLM backend (default values already point at the
catalog Ollama Service).

## Authentication

Open WebUI uses **its own login** rather than Dex / Traefik Forward Auth (see
Access). The first account created in the UI is admin.

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
