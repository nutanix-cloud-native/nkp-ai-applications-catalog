# Kubeflow Platform (Unified, Multi-User)

**Kubeflow Platform** is the glue layer that turns separate Kubeflow apps into
one multi-user experience: one URL, one login, and per-user workspaces. Auth is
Istio + NKP Dex + oauth2-proxy (not Traefik). Dedicated Istio gateway pods in
`kubeflow` sit behind LoadBalancer Service `kubeflow-ingressgateway`. The other
core pieces are `oauth2-proxy` (SSO / `kubeflow-userid` injection) and the
Profiles controller/`Profile` CRD for namespace isolation and RBAC.

---

## Install it (the whole flow)

Auth is **Istio + NKP Dex + oauth2-proxy** (inline reverse-proxy, not Traefik
and not Istio `ext_authz`). Dashboard and Pipelines charts route their
VirtualServices at `oauth2-proxy`, so enable **Platform first**.

1. In the workspace (NKP UI → Workspace Catalog, or a GitOps `AppDeployment`),
   enable **cert-manager** and **istio-helm**. Dex is already on the management
   plane; this app requires it.
2. (Optional) Set `config.kubeflowIngressHost` for a friendly DNS name (and
   optionally `config.kubeflowIngressURL` with that host, e.g. `https://…`).
   If host is left empty, the app installs with a placeholder and `secret-syncer`
   updates oauth2-proxy, Dex redirect URIs, and the Kommander Launch tile once
   the dedicated LoadBalancer receives an IP. Do not set URL without a host.
3. Enable **Kubeflow Platform**.
4. Open Kubeflow from the workspace **Application Dashboards** tab (tile
   **Kubeflow Platform**) once the Launch URL is populated, **or** look up the
   dedicated LoadBalancer IP and open it in a browser. Enable **Kubeflow Central
   Dashboard** and **Kubeflow Pipelines** so `/` and `/pipeline/` have backends:

```sh
# The single Kubeflow entry point (dedicated LB Service):
kubectl -n kubeflow get svc kubeflow-ingressgateway \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
# e.g. <kubeflow-load-balancer-address>  ->  open http://<that-address>/
```

You'll see a **"Sign in with Dex"** page → the **NKP Dex** login (the same
account you use for the NKP/Kommander console) → then the **Central Dashboard**.
Component UIs live under the same URL by path: `…/` (dashboard),
`…/pipeline/` (Pipelines). Other header-auth UIs (for example `/katib/`) can
be added later; they are not catalog apps today.

The Kommander Launch tile is a workspace ConfigMap (`${releaseName}-ui`).
`secret-syncer` patches `dashboardLink` to `http://<host>/` after the LB
assigns an address (or to your host/URL when `config.kubeflowIngressHost` is
set). Until then the tile may show without a working link.

Do not use `kubectl port-forward` to the component UIs for login. Identity
headers come from oauth2-proxy on the dedicated ingress URL.

> Your browser may warn about Dex's self-signed certificate on a test cluster -
> accept it. For production, trust the NKP CA bundle instead.

---

## HTTPS / TLS Edge Termination

The chart provides generic, catalog-wide HTTPS edge termination on the dedicated
Istio gateway (`kubeflow-ingressgateway`). **Self-signed TLS is enabled by
default** — the chart bootstraps a CA and leaf certificate via cert-manager on
install (cert-manager must be enabled in the workspace catalog). To switch
modes (for example, to bring your own certificate), set `tls.mode` to
`existingSecret` or `certManager` while keeping `tls.enabled: true`. To
disable TLS entirely (HTTP only), set `tls.enabled: false`.

When TLS is enabled (the default), the gateway serves HTTPS on port **443**.
HTTP/80 is also configured when `redirectHttpToHttps: true` (the default) so
that HTTP traffic is redirected to HTTPS rather than hanging. Set
`redirectHttpToHttps: false` to expose port 443 only (HTTP/80 is omitted) for
a fail-closed edge. The gateway `hosts` is set to `["*"]` to
avoid SNI validation errors when the ingress host is a bare LoadBalancer IP
address (which is not a valid SNI hostname).

### TLS modes

| Mode | Use case | Resources created | Pre-reqs |
|---|---|---|---|
| `existingSecret` | Customer brings their own TLS certificate | None (reference only) | Pre-create a Secret with `tls.crt` / `tls.key` |
| `certManager` | cert-manager provisions via an Issuer | A `Certificate` | cert-manager installed; `tls.issuerRef` set |
| `selfSigned` | One-click dev / test cluster | CA Issuer + CA Secret + leaf `Certificate` + a ConfigMap publishing the CA cert | cert-manager installed |

### Enabling TLS

TLS is on by default (`mode: selfSigned`). To switch modes or disable entirely:

```yaml
# Default (self-signed via cert-manager):
tls:
  enabled: true
  mode: selfSigned
  secretName: kubeflow-tls
config:
  kubeflowIngressHost: <external-ip-or-dns>

# Disable TLS (HTTP only):
tls:
  enabled: false

# Customer-provided certificate:
tls:
  enabled: true
  mode: existingSecret
  secretName: my-tls-secret
config:
  kubeflowIngressHost: kubeflow.example.com
```

For **cert-manager** mode, supply:

```yaml
tls:
  mode: certManager
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
    group: cert-manager.io
```

For **existingSecret** mode, simply point at a pre-existing Secret (no
cert-manager resources are rendered):

```yaml
tls:
  enabled: true
  mode: existingSecret
  secretName: my-tls-secret
config:
  kubeflowIngressHost: kubeflow.example.com
```

### TLS RBAC

The gateway ServiceAccount is granted a namespace-scoped `Role` allowing
`get`/`list`/`watch` on Secrets so Istio's SDS server can fetch and refresh the
TLS credential. This is automatically created when TLS is enabled and removed
(Helm prune) when disabled.

### Security notes

- **mTLS**: Traffic between Istio gateway pods and backend services (oauth2-proxy,
  Kubeflow components) uses Istio mTLS — unchanged by this TLS setup. The
  edge TLS only secures the outer ingress hop.
- **Certificate renewal**: The leaf certificate auto-renews 360h (15 days) before
  expiry and rotates via cert-manager's `Always` policy. The CA certificate
  persists for 10 years. Envoy picks up rotated certs without pod restarts.
- **Static IP**: The LoadBalancer IP must match a SAN in the certificate. An IP
  requires an IP SAN (auto-detected), while a hostname requires a DNS SAN.
- **Cookie security**: `cookie_secure=true` is set when TLS is enabled, preventing
  cookies over plaintext HTTP.

### Trusting the self-signed CA

In `selfSigned` mode the CA certificate is published in a ConfigMap named
`<tls.name>-ca` in the app namespace. Download it to trust the leaf certificate
in browsers/clients:

```sh
kubectl -n kubeflow get configmap kubeflow-platform-ca \
  -o jsonpath='{.data.ca\.crt}' > kubeflow-ca.crt
```

> **Tip:** Use `kubectl -n kubeflow get configmap -l app.kubernetes.io/component=tls`
> to discover the exact name if `tls.name` was customized.

The chart never publishes the CA private key or falls back to HTTP without
explicit redirect configuration. When TLS is enabled, HTTPS is served on port
443. If `redirectHttpToHttps: true` (the default), HTTP/80 is also configured
to redirect to HTTPS, so HTTP traffic does not hang. If
`redirectHttpToHttps: false`, HTTP/80 is not configured (fail-closed on the
edge service). A configured hostname must be covered by
the certificate; a bare LoadBalancer IP requires an IP SAN and is generally
unsuitable for publicly trusted certificates.

---

### Switching TLS modes

| From → To | Notes |
|---|---|
| `existingSecret` → `selfSigned` | Set `mode: selfSigned`; cert-manager creates the CA + leaf cert |
| `selfSigned` → `existingSecret` | Pre-create a Secret at `tls.secretName`, then switch `mode` |
| Any → `existingSecret` | No cert-manager resources are rendered; the gateway reads your existing Secret |

`existingSecret` mode requires **no extra resources or issuer** — just a
pre-existing Secret with `tls.crt` and `tls.key`. The chart still creates the
TLS RBAC Role so the gateway SA can read your Secret. This flow cannot conflict
with `selfSigned` or `certManager` because they use different `mode` values and
different sets of rendered resources.

---

## Ingress host and overrides

The ingress **host** is the primary knob (optional). Leave it empty to let the
syncer discover the LoadBalancer IP or hostname; set it for a friendly DNS name.
`config.kubeflowIngressURL` is an optional override that defaults to
`http://<host>` — set it only **with** a host (for example to force `https://…`).
URL alone (without host) is not supported.

If you need to look up the value before enabling, use the known external
address your platform team assigned for this Service. For already-provisioned
environments, you can inspect it with:

```sh
kubectl -n kubeflow get svc kubeflow-ingressgateway \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
# or, if your environment returns DNS:
kubectl -n kubeflow get svc kubeflow-ingressgateway \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Then set:

```yaml
config:
  kubeflowIngressHost: "<external-ip-or-dns>" # optional; empty uses the allocated LB address
  # optional; defaults to http://<kubeflowIngressHost>. Do not set without a host.
  kubeflowIngressURL: ""
  # Dex claim copied into kubeflow-userid. Profile.owner must match this value.
  # Default email. Username-only Dex (no email claim) can set preferred_username.
  # Changing this after Profiles exist orphans those workspaces.
  userIDClaim: email
```

Other fields continue to auto-derive/generate:

| Setting | Auto-behavior | Override (app config) |
| --- | --- | --- |
| Dex issuer URL | Derived from `kommander-vars.ingressAddress` (`https://<addr>/dex`) | `config.dexIssuerURL` |
| Ingress host | Explicit host wins; otherwise syncer discovers the dedicated LB address | `config.kubeflowIngressHost` |
| Ingress URL | Defaults to `http://<host>`, or `https://<host>` when `tls.enabled` is true | `config.kubeflowIngressURL` |
| User id claim | `email` → `kubeflow-userid`; Profile.owner must equal that value | `config.userIDClaim` |
| OIDC client & cookie secrets | Generated once, then preserved across upgrades | `config.oauth2ClientSecret`, `config.oauth2CookieSecret` |

To override anything, set it under `config` in the app's configuration
(Kommander UI → the app → Configuration, or an `AppDeployment`'s
`configOverrides`).

---

## Add users (from the UI, no kubectl)

A "user" is whoever **NKP Dex** authenticates, identified by the claim in
`config.userIDClaim` (default **email**). Give someone a private workspace by
listing them under `profiles` in this app's configuration:

```yaml
profiles:
  - name: alice          # becomes the namespace name
    owner: alice@example.com   # MUST equal kubeflow-userid (config.userIDClaim)
  - name: bob
    owner: bob@example.com
```

Each entry creates that user's isolated namespace with
`kubeflow-admin/edit/view` RBAC. Editing the list from the Kommander UI is all
it takes - no `kubectl`.

> **Careful:** removing a user from the list deletes their namespace (and its
> contents). To offboard without data loss, move the namespace out of the app's
> management first. Admins can also create Profiles directly with `kubectl`
> instead of listing them here.

### How Access Works

- `kubeflow-platform` does not create a special admin user; users authenticate via NKP Dex, and access is controlled by Kubernetes/Kubeflow RBAC.
- A Dex login alone does not create a workspace. Regular users need a `Profile` (via the `profiles` list above) to get namespace-scoped access.
- Cluster-admin users get broad visibility, including the dashboard's **All namespaces** view; regular users see only their own profile namespace(s).
- Self-service namespace creation requires explicit RBAC (`create` on `profiles.kubeflow.org`) and should be scoped to trusted groups.

---

<details>
<summary>Add a component app to the unified URL</summary>

Integrate a new component with two lists in `values.yaml` (override them from the
Kommander UI / `configOverrides` — no chart edit or rebuild):

1. **A route** so the component's UI is reachable behind the single login. Append to
   `routes` (oauth2-proxy authenticates once against Dex, then path-routes):

```yaml
routes:
  - id: model-registry
    path: /model-registry/                       # keep the trailing slash
    uri: http://model-registry-ui.kubeflow.svc.cluster.local
```

2. **A Profile namespace label** if the component's controller/webhook keys off one,
   so it acts on every user namespace:

```yaml
profileNamespaceLabels:
  modelregistry.kubeflow.org/enabled: "true"
```

Then, for discoverability, add a Central Dashboard menu/external link, and make sure
the component ships an Istio `VirtualService` bound to `kubeflow-gateway` (its upstream
manifests usually do).

> **Decision rule:** route a component here **only if it can't do OIDC** — it will
> trust the injected `kubeflow-userid` header. An **OIDC-capable** app (e.g.
> JupyterHub) must instead be its own Dex client on its own ingress; do not list it in
> `routes` (stacking OIDC behind this proxy causes a double login + CSRF/500).

---

</details>

<details>
<summary>Production readiness guidance</summary>

The default chart values are intentionally minimal and functional for small clusters.
For production, tune capacity and resiliency explicitly.

### 1) Scale and size the data path (`oauth2-proxy`)

`oauth2-proxy` is the primary request path for unified Kubeflow traffic. Scale this
first as concurrent users and artifact/API traffic grow.

Suggested starting profile:

```yaml
workloads:
  oauth2proxy:
    replicas: 2
    resources:
      requests:
        cpu: 250m
        memory: 512Mi
      limits:
        cpu: "1"
        memory: 1Gi
```

Increase replicas/resources as browser traffic, large artifact downloads, and MLMD calls rise.

### 2) Keep control-plane reconciliation stable (Profiles controller)

Profiles is typically light compared to UI traffic, but should still have explicit requests:

```yaml
workloads:
  profiles:
    replicas: 1
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
```

Use `replicas: 2` only when your environment has heavy or bursty profile churn.

### 3) Spread critical pods across nodes

Use node placement controls to avoid single-node concentration:

```yaml
workloads:
  oauth2proxy:
    nodeSelector: {}
    tolerations: []
    affinity: {}
  profiles:
    nodeSelector: {}
    tolerations: []
    affinity: {}
```

At minimum, add anti-affinity or topology spread for `oauth2-proxy`.

### 4) Protect availability during disruptions

This chart does not currently ship PodDisruptionBudgets. For production, add PDBs
through your normal overlay/patch workflow:

- `oauth2-proxy`: `minAvailable: 1` when replicas >= 2
- `profiles` controller: PDB optional unless replicas >= 2

### 5) Secure transport and trust chain

- Replace test self-signed trust with your production issuer/CA chain.
- Keep Dex/OIDC endpoints reachable and certificate validation strict in production.
- Restrict external exposure to only the intended ingress path.

### 6) Operability checks before go-live

- Verify auth redirect and callback from outside cluster network.
- Validate tenant isolation:
  - user can access own namespace
  - user cannot access other namespaces
- Run rolling restart and node-drain exercises to confirm no full outage at steady state.

---

</details>

## Troubleshooting

- **Pipelines run stuck in `Pending` with `secret "mlpipeline-minio-artifact" not found`** -
  this app now deploys a `secret-syncer` that automatically copies the artifact
  credential secret from `kubeflow` into every Profile namespace
  (`pipelines.kubeflow.org/enabled=true`). If this still appears, verify the
  syncer is running and the Profile namespace has the label:

```sh
kubectl -n kubeflow get deploy secret-syncer
kubectl get ns --show-labels
kubectl -n <profile-namespace> get secret mlpipeline-minio-artifact
```

- **Pipelines run stuck in `Pending` with `0/.. nodes available ... Insufficient cpu`** -
  this is scheduler pressure, not Kubeflow auth. Verify with:

```sh
kubectl -n <profile-namespace> get events --sort-by=.lastTimestamp
kubectl -n <profile-namespace> get pods -o wide
```

  If needed, reduce request/limit defaults for user pipeline tasks or scale down other
  workloads before re-running.

- **Runs page error `Cannot find context ... typeName:"system.PipelineRun"`** -
  this usually appears when a run partially initializes MLMD context and then fails
  early (for example, Pending/Failed driver pods). Re-run after fixing the underlying
  workflow blocker; the new run writes a consistent PipelineRun context.

- **`oauth2-proxy` restarts once or twice at first start** - it can begin OIDC
  discovery before Dex has reloaded the newly-registered client; it recovers on
  its own.
- **Katib UI shows `401 user header not present` on a raw port-forward** -
  expected; identity is injected by oauth2-proxy, so use the ingress URL, not a
  port-forward.
- **`kubeflow` namespace ownership** - `kubeflow-pipelines` / `spark-operator`
  also target the shared `kubeflow` namespace. This app does not own that
  namespace (it uses `createNamespace`), so disabling it won't prune the others.

---

<details>
<summary>Notes for maintainers</summary>

- The app is chart-backed (`type: nkp-catalog`): `charts/kubeflow-platform/` is a
  hand-authored Helm chart (this is glue, not a baked upstream flatten). The app
  wraps it with an `OCIRepository` + `HelmRelease` like the other catalog apps.
- Self-configuration lives in `templates/_helpers.tpl` (`kubeflow-platform.derived`):
  explicit `config.*` values take precedence, then the generated Secret and live
  LoadBalancer status supply the host (URL defaults to `http://<host>`),
  and `randAlphaNum` + lookup-preserve keep secrets stable across upgrades.
  Offline (`helm template`/lint) lookups are empty, so live-cluster host assertions
  only run when the cluster API is reachable.
- The integration surface is **data, not code**: `templates/auth.yaml` renders the
  oauth2-proxy upstreams from `.Values.routes`, and `templates/profiles.yaml` renders
  the Profile namespace labels from `.Values.profileNamespaceLabels`. Adding a
  component is a values entry (see "Add a component app"), keeping the chart open for
  extension without edits.

</details>
