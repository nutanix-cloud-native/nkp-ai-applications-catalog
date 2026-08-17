# Kubeflow Platform (Unified, Multi-User)

**Kubeflow Platform** is the glue layer that turns separate Kubeflow apps into
one multi-user experience: one URL, one login, and per-user workspaces. It
reuses NKP Dex for identity and `istio-helm` ingress for entry, so there is no
second auth or ingress stack to operate. The core pieces are a shared
`kubeflow-gateway`, `oauth2-proxy` for SSO/header injection, and the Profiles
controller/`Profile` CRD for namespace isolation and RBAC.

---

## Install it (the whole flow)

1. In the workspace (NKP UI → Workspace Catalog, or a GitOps `AppDeployment`), enable
   **cert-manager**, **istio-helm**, and **Kubeflow Central Dashboard** (plus any
   components you want: Pipelines, Katib).
2. Enable **Kubeflow Platform**. That's it - it configures itself (see below).
3. Open the one URL and log in:

```sh
# The single entry point (address of the ingress gateway):
kubectl -n istio-helm-gateway-ns get svc istio-helm-ingressgateway \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
# e.g. 10.22.203.228  ->  open http://<that-address>/
```

You'll see a **"Sign in with Dex"** page → the **NKP Dex** login (the same
account you use for the NKP/Kommander console) → then the **Central Dashboard**.
Component UIs live under the same URL by path: `…/` (dashboard),
`…/pipeline/` (Pipelines), `…/katib/` (Katib).

> Your browser may warn about Dex's self-signed certificate on a test cluster -
> accept it. For production, trust the NKP CA bundle instead.

---

## Zero-config, and how to override

On enable the chart figures everything out from the cluster, so an operator
never has to look up addresses or run `openssl`:

| Setting | Auto-behavior | Override (app config) |
| --- | --- | --- |
| Dex issuer URL | Derived from `kommander-vars.ingressAddress` (`https://<addr>/dex`) | `config.dexIssuerURL` |
| Ingress URL / host | Read from the `istio-helm-ingressgateway` LoadBalancer | `config.kubeflowIngressURL`, `config.kubeflowIngressHost` |
| OIDC client & cookie secrets | Generated once, then preserved across upgrades | `config.oauth2ClientSecret`, `config.oauth2CookieSecret` |

If istio-helm isn't Ready yet, the app simply retries until the ingress address
exists - no action needed. To override anything, set it under `config` in the
app's configuration (Kommander UI → the app → Configuration, or an
`AppDeployment`'s `configOverrides`).

---

## Add users (from the UI, no kubectl)

A "user" is whoever **NKP Dex** authenticates, identified by their login
**email**. Give someone a private workspace by listing them under `profiles` in
this app's configuration:

```yaml
profiles:
  - name: alice          # becomes the namespace name
    owner: alice@example.com   # MUST equal the user's Dex login email
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
  cluster `lookup` for the addresses, `randAlphaNum` + lookup-preserve for the
  secrets. Offline (`helm template`/lint) lookups are empty and the cluster-only
  assertions are skipped.
- The integration surface is **data, not code**: `templates/auth.yaml` renders the
  oauth2-proxy upstreams from `.Values.routes`, and `templates/profiles.yaml` renders
  the Profile namespace labels from `.Values.profileNamespaceLabels`. Adding a
  component is a values entry (see "Add a component app"), keeping the chart open for
  extension without edits.

</details>
