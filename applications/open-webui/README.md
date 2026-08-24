# open-webui

Open WebUI is an extensible, self-hosted web interface for interacting with
large language models.

## Authentication

Open WebUI uses NKP SSO by default. Users authenticate via Traefik Forward Auth
and Dex before reaching Open WebUI. The authenticated username is passed via the
`X-Forwarded-User` header and mapped with trusted-header SSO.

The first user to sign in is created automatically (`sso.enableSignup: true`).
Grant admin access in the Open WebUI admin settings after the first login.

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
