# jupyterhub

JupyterHub brings the power of notebooks to groups of users. It gives users access to computational environments and resources without burdening the users with installation and maintenance tasks.

## Authentication

JupyterHub uses NKP SSO by default. Users authenticate via Traefik Forward Auth and Dex before reaching JupyterHub. The authenticated username is passed via the `X-Forwarded-User` header.

### Admin Users

By default, no users have admin privileges. To grant admin access, add usernames to the `admin_users` list via **Workspace Configuration**:

```yaml
hub:
  config:
    Authenticator:
      admin_users:
        - alice@company.com
        - bob@company.com
```

Usernames must match exactly what Dex returns (typically email addresses).

**What admins can do:**

- Access the Admin panel (`/nkp/jupyter/hub/admin`)
- Start/stop other users' servers
- Add/remove users
- Access other users' notebooks (if configured)

## Chart Source

The JupyterHub Helm chart is hosted in a **traditional Helm repository**, not an
OCI registry. It must be pulled locally and pushed to your OCI registry before
the NKP catalog can use it.

Source metadata is stored in `.catalog-source.yaml`:

```yaml
helmrepo: jupyterhub/jupyterhub
helmrepoUrl: https://hub.jupyter.org/helm-chart/
ocipush: oci://ghcr.io/nutanix-cloud-native/charts/jupyterhub
```

### How to push the chart to your OCI registry

```bash
# 1. Add the upstream Helm repository
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
helm repo update

# 2. Pull the chart version used by this catalog entry
helm pull jupyterhub/jupyterhub --version 4.3.2

# 3. Push to your OCI registry
helm push jupyterhub-4.3.2.tgz oci://ghcr.io/nutanix-cloud-native/charts
```

After pushing, update the OCI URL in `helmrelease/helmrelease.yaml` and
`.catalog-source.yaml` to match your registry.

## Icon

The `icon` field in `metadata.yaml` is a base64-encoded SVG. It was generated
from the jupyterhub icon in wikimedia.org:

| Field | Value |
|-------|-------|
| Source URL | `https://upload.wikimedia.org/wikipedia/commons/3/38/Jupyter_logo.svg` |
| Format | SVG (base64-encoded) |

To regenerate:

```bash
curl -sL https://upload.wikimedia.org/wikipedia/commons/3/38/Jupyter_logo.svg | base64 | tr -d '\n'
```

## Links

- [jupyterhub.io](https://jupyterhub.io)
- [GitHub (jupyterhub)](https://github.com/jupyterhub/jupyterhub)
- [GitHub (Helm chart)](https://hub.jupyter.org/helm-chart/)
