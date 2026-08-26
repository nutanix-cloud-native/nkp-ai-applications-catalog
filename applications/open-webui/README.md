# open-webui

Open WebUI is an extensible, self-hosted web interface for interacting with
large language models.

## Authentication (NKP SSO)

Open WebUI does **not** support a URL prefix. In production the UI calls
`/api/config` on the page origin, so `/nkp/open-webui/` cannot work.

NKP SSO uses **host-based** Traefik Forward Auth:

- Service type **ClusterIP**
- Chart Ingress at path `/` with `kommander-traefik`
- Middleware: `${releaseNamespace}-forwardauth` only (no stripPrefix)
- Open WebUI trusted-header SSO on `X-Forwarded-User`

Set Helm value `ingress.host` to an FQDN that resolves to this cluster's
`kommander-traefik` LoadBalancer. A post-install Job copies that host into
the Launch ConfigMap as `https://<host>/`.

Users authenticate with Dex before reaching Open WebUI. The first account is
created automatically (`sso.enableSignup: true`). Grant admin in Open WebUI
settings after the first login.

Direct ClusterIP or port-forward access skips Forward Auth.

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
