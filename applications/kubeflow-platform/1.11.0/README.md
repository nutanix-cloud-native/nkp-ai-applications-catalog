# Kubeflow Platform (Unified, Multi-User)

Enable the Kubeflow catalog apps (Central Dashboard, Pipelines, Katib, ...) on
their own and each is a separate island with its own sign-in. **Kubeflow
Platform** is the glue that joins them into **one website, one login, and a
private workspace per user** - by reusing NKP's own **Dex** (login) and
**istio-helm** ingress. No second identity system, no extra ingress stack.

It installs, into the shared `kubeflow` namespace (plus a Dex client in
`kommander` and a few cluster-wide roles):

| Piece | Purpose |
| --- | --- |
| `kubeflow-gateway` (Istio `Gateway`) | The single entry point; binds to `istio-helm-ingressgateway`. |
| `oauth2-proxy` | Logs users in against NKP Dex and injects the `kubeflow-userid` / `kubeflow-groups` headers the UIs need. |
| Profiles controller + `Profile` CRD | Turns a user into an isolated namespace with RBAC (`profiles-kfam` is what the dashboard talks to). |
| `kubeflow-admin/edit/view` ClusterRoles | Base roles that per-user RBAC and the component roles build on. |

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

### What "All namespaces" in the dashboard means

The dashboard's namespace dropdown scopes the UI to one workspace. A regular
user sees only the workspace(s) they own. **"All namespaces"** is the
**cluster-admin** view - it appears because you're logged in with an NKP admin
identity (cluster-wide RBAC), so Kubeflow treats you as an admin. A normal user
(one with a `Profile` but not cluster-admin) won't see it; they're scoped to
their own namespace. Seeing it is expected, not a misconfiguration.

---

## Add a component app to the unified URL

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

## Troubleshooting

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

## Notes for maintainers

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
