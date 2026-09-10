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

Open WebUI is therefore a **ClusterIP** Service (not on NKP Traefik). Access it
with port-forward:

```bash
kubectl -n open-webui port-forward svc/open-webui 8080:80
```

Then open `http://127.0.0.1:8080/`.

In-cluster: `http://open-webui.open-webui.svc.cluster.local:80` (same namespace:
`http://open-webui:80`).

Open WebUI does **not** declare a catalog dependency on Ollama.
`ollama.enabled: false` only disables the Helm chart's bundled Ollama
subchart (upstream default is enabled). It does not require the catalog
Ollama app.

To point Open WebUI at catalog Ollama, set **App Config Overrides**. If Open WebUI already started once, also disable persistent config so SQLite does not keep `host.docker.internal` / `ENABLE_OLLAMA_API=False`:

```yaml
ollamaUrls:
  - "http://ollama-ollama.ollama.svc.cluster.local:11434"
extraEnvVars:
  - name: ENABLE_PERSISTENT_CONFIG
    value: "False"
  - name: OLLAMA_BASE_URL
    value: "http://ollama-ollama.ollama.svc.cluster.local:11434"
```

Confirm on the **StatefulSet** (not a Deployment):

```bash
kubectl -n open-webui get sts open-webui -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep -iE 'ollama|persistent'
```

Look in **Admin → Settings → Connections**, not only the chat model picker. Models appear after Ollama has pulled at least one (catalog Ollama pulls `llama3.2`).

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
| Format | PNG (resized to 512x512, base64-encoded) |

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
