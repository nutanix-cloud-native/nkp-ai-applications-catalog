# jupyterhub

JupyterHub brings the power of notebooks to groups of users. It gives users access to computational environments and resources without burdening the users with installation and maintenance tasks.

## Single sign-on with NKP (Dex)

By default this app uses `DummyAuthenticator` (one shared password). For production,
configure JupyterHub as an OIDC client of **NKP Dex** so users sign in with the
**same credentials as the NKP console and Kubeflow** — one login, no separate user
store, whether JupyterHub is opened standalone or from the Kubeflow dashboard.

This is an admin-applied setup: the upstream Zero-to-JupyterHub chart speaks OIDC but
can't self-derive cluster addresses.

> **Note:** JupyterHub authenticates against Dex on **its own ingress** — do not route
> it through the unified Kubeflow `oauth2-proxy`. Users open it from NKP's
> **Application Dashboards**; an existing NKP session makes sign-in a silent SSO hop.

### 1. Gather the cluster addresses

```sh
# Dex address (issuer host):
kubectl -n kommander get cm kommander-vars -o jsonpath='{.data.ingressAddress}'
# unified Kubeflow ingress (Istio):
kubectl -n istio-helm-gateway-ns get svc istio-helm-ingressgateway \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### 2. Register JupyterHub as a Dex client (once)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: jupyterhub-oidc-client-secret
  namespace: kommander
stringData:
  client-secret: "REPLACE_ME"          # openssl rand -hex 24
---
apiVersion: dex.mesosphere.io/v1alpha1
kind: Client
metadata:
  name: jupyterhub                      # client_id becomes dex-controller-jupyterhub
  namespace: kommander
spec:
  clientSecretRef:
    name: jupyterhub-oidc-client-secret
  displayName: JupyterHub
  redirectURIs:
    # JupyterHub's OWN ingress (Traefik) — not the unified Kubeflow (Istio) ingress.
    - "http://<jupyterhub-ingress>/jupyter/hub/oauth_callback"
```

### 3. Configure the app (Workspace Configuration / `configOverrides`)

```yaml
hub:
  config:
    JupyterHub:
      authenticator_class: generic-oauth
    GenericOAuthenticator:
      client_id: dex-controller-jupyterhub
      client_secret: "<same value as the Secret above>"
      # JupyterHub's OWN ingress host (must match a redirectURI on the Dex Client):
      oauth_callback_url: http://<jupyterhub-ingress>/jupyter/hub/oauth_callback
      authorize_url: https://<dex-address>/dex/auth
      token_url:     https://<dex-address>/dex/token
      userdata_url:  https://<dex-address>/dex/userinfo
      login_service: "NKP (Dex)"
      scope: [openid, profile, email, groups]
      username_claim: email              # matches Kubeflow's kubeflow-userid
      validate_server_cert: false        # self-signed Dex cert on test clusters; see gotcha 1
    Authenticator:
      allow_all: true                # or restrict: allowed_users: [...] / allowed_groups: [...]
  networkPolicy:
    enabled: false                   # see gotcha 2
```

### NKP-specific gotchas (both required on this platform)

1. **Self-signed Dex cert** — on test clusters set
   `GenericOAuthenticator.validate_server_cert: false`. Use this key, not the older
   `tls_verify` alias, which z2jh silently ignores (leaving TLS on and 500-ing the token
   exchange with `SSL certificate problem: unable to get local issuer certificate`).

   **For production**, trust the NKP CA instead of disabling verification:

   ```yaml
   hub:
     config:
       GenericOAuthenticator:
         http_request_kwargs:
           ca_certs: /etc/ssl/certs/nkp-ca.crt   # mount the NKP CA into the hub pod
   ```

2. **Hub NetworkPolicy blocks Dex** — the chart's hub `NetworkPolicy` drops egress to
   the NKP ingress/Dex address, so the browser reaches the Dex login page but the hub's
   back-channel token exchange hangs. Keep the policy on and allow that one address:

   ```yaml
   hub:
     networkPolicy:
       enabled: true
       egress:
         - to:
             - ipBlock:
                 cidr: <nkp-ingress-ip>/32   # the NKP ingress address serving Dex
   ```

   On a test cluster you can instead set `hub.networkPolicy.enabled: false`.

After applying, the login page reads **"Sign in with NKP (Dex)"** and users
authenticate with their NKP account. An existing NKP session (e.g. arriving from the
Kubeflow dashboard) returns immediately — no second prompt.

### How users are created

With Dex sign-in there is **no JupyterHub user database** — a "user" is anyone your
NKP/Dex identity source knows (the same people who log into the NKP console). Manage
people in your IdP/Dex; JupyterHub only *authorizes* (`allow_all`, or
`allowed_users` / `allowed_groups`). This is identical for standalone and unified.


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
