# JupyterHub group profiles — zero to end test guide

End-to-end validation of:

1. Auth0 roles → Dex groups (`https://nkp/groups`)
2. Traefik Forward Auth URL RBAC (`/nkp/jupyter` via Workspace View)
3. Group-aware JupyterHub RemoteUser authenticator
4. Spawn profiles: Light / Medium / Heavy by group

## Prerequisites

- Auth0 roles `nkp-admins` and `nkp-users` exist and are assigned to test users.
- Auth0 Login Action sets claim `https://nkp/groups` from roles and is in the Login flow.
- Dex OIDC connector maps groups:

  ```yaml
  claimMapping:
    email: email
    preferred_username: email
    groups: https://nkp/groups
  ```

- Catalog branch with aggregating RBAC + group-aware Hub config
  (for example `feat/jupyterhub-workspace-view-rbac`).
- Kubeconfigs:
  - `workload.conf` — workload cluster
  - management kubeconfig (example: `nkp.cluster.navid.vlan173.final.conf`)

Replace the workspace namespace below if yours differs from
`navid-workload-cluster-01-lrrc7`.

---

## 0) Confirm Dex group claim mapping (management)

```bash
kubectl --kubeconfig=nkp.cluster.navid.vlan173.final.conf \
  -n kommander get connectors.dex.mesosphere.io -o yaml \
  | rg -n 'claimMapping|https://nkp/groups|groups:'
```

Confirm Auth0 Login Action still writes `https://nkp/groups` and is attached to
the Login flow.

---

## 1) Confirm JupyterHub is installed

```bash
kubectl --kubeconfig=workload.conf -n jupyterhub get deploy,pods,ingress
kubectl --kubeconfig=workload.conf get helmrelease -A | rg jupyterhub
```

Expect Hub/proxy Running and a HelmRelease in the workspace namespace.

---

## 2) Apply TFA URL RBAC (aggregating ClusterRoles)

These let Workspace View users hit `/nkp/jupyter` without `cluster-admin`.

```bash
cd /path/to/nkp-ai-applications-catalog

kubectl --kubeconfig=workload.conf apply -f \
  applications/jupyterhub/4.3.2/helmrelease/rbac.yaml

kubectl --kubeconfig=workload.conf get clusterrole \
  dkp-jupyterhub-view dkp-jupyterhub-edit dkp-jupyterhub-admin
```

Confirm aggregation into workspace-view:

```bash
kubectl --kubeconfig=workload.conf get -o yaml \
  "$(kubectl --kubeconfig=workload.conf get clusterrole -o name \
     | rg 'workspace-view-' | head -1)" \
  | rg -A6 '/nkp/jupyter'
```

---

## 3) Bind Auth0 Devs → Workspace View (not automatic)

Step 2 only folds `/nkp/jupyter` into `workspace-view`. Binding the IdP group
to that role is a separate Access Control step.

Find the VirtualGroup:

```bash
kubectl --kubeconfig=nkp.cluster.navid.vlan173.final.conf get virtualgroups
```

Look for Auth0 Devs with subject `oidc:nkp-users` (name like `auth0-devs-xxxxx`).

Create the binding (replace `VIRTUAL_GROUP_NAME` and namespace if needed):

```bash
kubectl --kubeconfig=nkp.cluster.navid.vlan173.final.conf apply -f - <<EOF
apiVersion: workspaces.kommander.mesosphere.io/v1alpha1
kind: VirtualGroupWorkspaceRoleBinding
metadata:
  name: auth0-devs-workspace-view
  namespace: navid-workload-cluster-01-lrrc7
  annotations:
    kommander.mesosphere.io/display-name: "Auth0 Devs — Workspace View"
spec:
  workspaceRoleRef:
    name: workspace-view
  virtualGroupRef:
    name: VIRTUAL_GROUP_NAME
EOF
```

Or in the NKP UI: workspace → Access Control → Auth0 Devs → **Workspace View**.

Verify:

```bash
kubectl --kubeconfig=nkp.cluster.navid.vlan173.final.conf \
  -n navid-workload-cluster-01-lrrc7 \
  get virtualgroupworkspacerolebinding auth0-devs-workspace-view -o yaml
```

---

## 4) Apply group-aware Hub config + Light / Medium / Heavy profiles

Catalog `cm.yaml` uses Flux placeholders. Substitute before `kubectl apply`.
The defaults ConfigMap lives in the **workspace** namespace, not `jupyterhub`.

```bash
cd /path/to/nkp-ai-applications-catalog
git checkout feat/jupyterhub-workspace-view-rbac
git pull

sed \
  -e 's/${releaseName}/jupyterhub/g' \
  -e 's/${appVersion}/4.3.2/g' \
  -e 's/${releaseNamespace}/navid-workload-cluster-01-lrrc7/g' \
  applications/jupyterhub/4.3.2/helmrelease/cm.yaml \
| kubectl --kubeconfig=workload.conf apply -f -
```

Expect: `configmap/jupyterhub-4.3.2-defaults configured`.

A warning about missing `last-applied-configuration` is normal for Flux-created
objects.

Do **not** apply the raw template with `-n jupyterhub`; placeholders such as
`${releaseNamespace}` will fail.

Verify config content:

```bash
kubectl --kubeconfig=workload.conf -n navid-workload-cluster-01-lrrc7 \
  get cm jupyterhub-4.3.2-defaults -o yaml \
  | rg -n 'async def authenticate|allow_all|LIGHT_PROFILE|HEAVY_PROFILE|oidc:nkp-admins|NotImplementedError'
```

Must see `async def authenticate` and the profile definitions.
Must **not** see `raise NotImplementedError` (that caused 500 on `/hub/login`).

### Authenticator fix (historical)

An earlier draft called `login_user(auth_model)` while
`Authenticator.authenticate()` raised `NotImplementedError`. JupyterHub always
invokes `authenticate()` from `login_user()`, which produced:

```text
500 GET /nkp/jupyter/hub/login
NotImplementedError
```

Current `cm.yaml` implements `authenticate(handler, data)` to read
`X-Forwarded-User` and `Impersonate-Group`, and sets `allow_all = True`
(TFA already gates access).

---

## 5) Reconcile HelmRelease + restart Hub

Updating the ConfigMap alone may not remount until Helm reconciles:

```bash
kubectl --kubeconfig=workload.conf -n navid-workload-cluster-01-lrrc7 \
  annotate helmrelease jupyterhub \
  reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --overwrite

kubectl --kubeconfig=workload.conf -n jupyterhub get deploy
kubectl --kubeconfig=workload.conf -n jupyterhub rollout restart deploy/jupyterhub-hub
kubectl --kubeconfig=workload.conf -n jupyterhub rollout status deploy/jupyterhub-hub --timeout=180s
```

Watch Hub start cleanly:

```bash
kubectl --kubeconfig=workload.conf -n jupyterhub logs deploy/jupyterhub-hub -f
```

Good signs:

- loading extra config such as `remoteuser_groups_profiles.py`
- authenticator is the custom RemoteUser class
- **no** `NotImplementedError` on `/hub/login`

While logging in, request logs should include headers like:

```text
X-Forwarded-User: admin@example.com
Impersonate-Group: system:authenticated, oidc:nkp-admins
```

or `oidc:nkp-users` for a Dev user.

---

## 6) UI test — Admin vs Dev profiles

### Admin (`nkp-admins` → `oidc:nkp-admins`)

1. Log into NKP as admin.
2. Open JupyterHub (`/nkp/jupyter`).
3. Spawn page should show:
   - Light Environment
   - Medium Environment
   - Heavy Environment
4. Start **Heavy** (or Medium) and wait until Running.

### Dev (`nkp-users` → `oidc:nkp-users`)

1. Log into NKP as dev (separate browser/profile or full logout first).
2. Open JupyterHub.
3. Spawn page should show:
   - Light Environment
   - Medium Environment
4. **Heavy must not appear.**
5. Start Light or Medium successfully.

These are **server spawn profiles** (CPU/memory), not JupyterLab kernel
dropdowns. Kernel choices come from packages in the selected image.

---

## 7) Verify pod resources match profile

### Do not use `psutil` for Kubernetes limits

Inside a notebook, code like this often reports the **node**, not the profile:

```python
import psutil
print(psutil.cpu_count(logical=False))
print(psutil.virtual_memory().total / (1024**3))
```

Example misleading output on both light and heavy pods:

```text
Physical CPU Cores: 8
Total RAM: 31.02 GB
```

That matches the worker node (for example 8 CPUs / ~31 GiB), not the KubeSpawner
`cpu_limit` / `mem_limit`. Profiles can still be applied correctly while `psutil`
looks identical.

### Authoritative check: pod resource specs

```bash
kubectl --kubeconfig=workload.conf -n jupyterhub get pods | rg '^jupyter-'

kubectl --kubeconfig=workload.conf -n jupyterhub get pod \
  jupyter-admin-example-com---258d8dc9 \
  jupyter-dev-example-com---eb2b6c0d \
  -o custom-columns=\
NAME:.metadata.name,\
CPU_LIM:.spec.containers[0].resources.limits.cpu,\
MEM_LIM:.spec.containers[0].resources.limits.memory
```

Example when profiles are working:

| Pod | CPU limit | Memory limit |
| --- | --- | --- |
| admin (heavy) | `4` | `8Gi` |
| dev (light) | `1` | `2Gi` |

Or per pod:

```bash
kubectl --kubeconfig=workload.conf -n jupyterhub get pod <user-pod> \
  -o jsonpath='{.metadata.name}{"\n"}{.spec.containers[0].resources}{"\n"}'
```

Expected limits from `kubespawner_override`:

| Profile | CPU | Memory | Who sees it |
| --- | --- | --- | --- |
| light | 1 | 2Gi | everyone (default) |
| medium | 2 | 4Gi | `oidc:nkp-users` and `oidc:nkp-admins` |
| heavy | 4 | 8Gi | `oidc:nkp-admins` only |

### Optional: read cgroup quotas from inside the notebook

```python
from pathlib import Path

def read_cgroup(path):
    p = Path(path)
    return p.read_text().strip() if p.exists() else None

# cgroup v2 (common on modern clusters)
print("memory.max:", read_cgroup("/sys/fs/cgroup/memory.max"))
print("cpu.max:", read_cgroup("/sys/fs/cgroup/cpu.max"))
```

Interpretation:

- `memory.max` like `8589934592` ≈ 8Gi; `2147483648` ≈ 2Gi; `max` means unlimited.
- `cpu.max` like `400000 100000` ≈ 4 CPUs; `100000 100000` ≈ 1 CPU.

### What limits mean at runtime

- **Memory:** the cgroup enforces the cap; exceeding it can OOMKill the container.
  You do not get the full node RAM.
- **CPU:** CFS throttling applies under load. On an idle node, light and heavy can
  feel similar until you burn CPU.

Quick stress comparison (optional):

```python
import time
import multiprocessing as mp

def burn(_):
    t = time.time()
    while time.time() - t < 20:
        _ = hash(str(t))

# 8 workers: light (1 CPU) throttles harder than heavy (4 CPUs)
with mp.Pool(8) as p:
    p.map(burn, range(8))
```

---

## 8) If spawn fails with Nutanix VG 404 (storage, not RBAC)

Stale user PVC pointing at a deleted Volume Group looks like:

```text
FailedAttachVolume ... GetVG failed ... 404 NOT FOUND
Spawn failed: pod ... did not start in 300 seconds!
```

Delete the affected **user** PVC(s), not the Hub DB PVC:

```bash
kubectl --kubeconfig=workload.conf -n jupyterhub get pvc
kubectl --kubeconfig=workload.conf -n jupyterhub delete pvc claim-<user-hash>
```

Then spawn again so a new PVC is provisioned.

If a PV sticks in Terminating:

```bash
kubectl --kubeconfig=workload.conf patch pv <pv-name> \
  --type=merge -p '{"metadata":{"finalizers":null}}'
```

---

## Failure cheat sheet

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| 401 / Unauthorized on `/nkp/jupyter` | Missing aggregating ClusterRoles or Dev not bound to Workspace View | Steps 2–3 |
| 500 on `/hub/login` + `NotImplementedError` | Old authenticator stub | Re-apply fixed `cm.yaml` (step 4) + restart (step 5) |
| Login works but wrong / missing profiles | Groups not reaching Hub | Check Dex claimMapping, Auth0 Action, `Impersonate-Group` in Hub logs |
| Profiles correct, spawn times out / FailedAttachVolume | Stale Nutanix PVC | Step 8 |
| Light and heavy notebooks both show ~8 CPUs / ~31 GiB via `psutil` | `psutil` reads node capacity, not pod limits | Check pod `.spec.containers[0].resources` or cgroup (step 7) |
| `kubectl apply -f cm.yaml` namespace placeholder error | Applied Flux template raw | Use `sed` substitution (step 4) |
| Binding NotFound in workspace A after creating in workspace B | Binding is per workspace namespace | Recreate VirtualGroupWorkspaceRoleBinding in the current workspace ns |

---

## What is automatic vs manual

| Piece | Automatic with app? |
| --- | --- |
| `dkp-jupyterhub-*` ClusterRoles | Yes when catalog deploys (or apply `rbac.yaml`) |
| Group-aware authenticator + Light/Medium/Heavy | Yes when catalog defaults ship (or apply `cm.yaml` via sed) |
| Auth0 Devs → Workspace View binding | **No** — Access Control / kubectl once per workspace |
| Dex `claimMapping.groups` | **No** — IdP connector setup |

---

## Related docs

- [README.md](README.md) — operator overview
- [ACCESS.md](ACCESS.md) — RBAC design, workarounds, Design A/B profile mapping
