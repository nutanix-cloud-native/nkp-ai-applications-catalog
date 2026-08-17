# TODO: manual steps after this commit (delete this file)

This commit is on `snimar/kubeflow-multiuser-dedicated-lb` (not `main`).
Bake was run locally for `kubeflow-central-dashboard` `1.10.0`; `istio.io/rev: istio-helm` and `kubeflow/kubeflow-gateway` are in the baked chart.

## 1. Push this branch

```bash
git push -u origin snimar/kubeflow-multiuser-dedicated-lb
```

GitHub is not enough for the cluster. Catalog `HelmRelease` objects pull **OCI charts**, not git.

## 2. Package and push OCI charts

`applications/kubeflow-platform/1.11.0/helmrelease/helmrelease.yaml` currently points at `oci://ghcr.io/snimars/charts/kubeflow-platform`. Push a new `1.11.0` (or bump the tag in the HelmRelease if you do not overwrite).

```bash
# from repo root, after just login / helm registry login
helm package charts/kubeflow-platform
helm push kubeflow-platform-1.11.0.tgz oci://ghcr.io/snimars/charts

helm package charts/kubeflow-central-dashboard
helm push kubeflow-central-dashboard-1.10.0.tgz oci://ghcr.io/snimars/charts
# or: just push-kubeflow-central-dashboard

# Pipelines chart also changed (PVC keep + size values). Re-push 2.15.0.
helm package charts/kubeflow-pipelines
helm push kubeflow-pipelines-2.15.0.tgz oci://ghcr.io/snimars/charts
```

If the cluster HelmRelease still has `ref.tag: 1.11.0` (or Pipelines `2.15.0`) and you overwrite that tag, Flux may not see a digest change. Bump the tag **or** poke the HelmRelease (`flux reconcile helmrelease -n <workspace> kubeflow-platform` and `kubeflow-pipelines`).

## 3. Enable order on the NKP workspace

Do **not** pre-create `mlpipeline-minio-artifact`. Pipelines owns that secret.

1. `istio-helm`
2. `dex`
3. `kubeflow-platform` (creates `kubeflow` ns + dedicated LB)
4. `kubeflow-pipelines` (creates `mlpipeline-minio-artifact`; syncer copies it into profile namespaces)
5. `kubeflow-central-dashboard`

`secret-syncer` is a **Deployment** (`kubectl -n kubeflow get deploy secret-syncer`). It waits for the Pipelines secret and labels `kubeflow`, `kubeflow-central-dashboard`, and `katib` with `istio.io/rev=istio-helm`, then rollouts **once** when the label is first applied.

## 4. Prove dedicated LB (not shared istio-helm)

```bash
kubectl -n kubeflow get svc,deploy kubeflow-ingressgateway
kubectl -n istio-helm-gateway-ns get svc istio-helm-ingressgateway

KF=$(kubectl -n kubeflow get svc kubeflow-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
IG=$(kubectl -n istio-helm-gateway-ns get svc istio-helm-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "kubeflow=$KF  istio-helm=$IG"   # must differ

kubectl -n kubeflow get gateway kubeflow-gateway -o yaml | grep -A2 selector
# expect: istio: kubeflow-ingressgateway

curl -sS -o /dev/null -w "%{http_code}\n" "http://$KF/ping"
kubectl -n kommander get client.dex.mesosphere.io kubeflow-oauth2-proxy -o jsonpath='{.spec.redirectURIs[0]}{"\n"}'
# expect http://$KF/oauth2/callback

kubectl get ns kubeflow kubeflow-central-dashboard -L istio.io/rev
kubectl -n kubeflow get pods
# 2/2 on oauth2-proxy, profiles, dedicated gateway, most pipeline UIs
# 1/1 is expected on metacontroller, metadata-envoy, profile-controller (inject: false)
```

## 5. Upgrades, restarts, and storage

Helm upgrades and pod restarts keep the settings below. Flux reconciles these HelmReleases every 15s; that is in-place (same object names), not a wipe. Uninstalling **Pipelines** is the data-loss path unless noted.

### What is preserved

| Thing | Helm upgrade / pod restart | Uninstall Pipelines or Platform |
| --- | --- | --- |
| OIDC client + cookie secrets | Yes (`lookup` on `kubeflow-platform-generated`) | Gone with Platform |
| Dex Client + redirect URI | Yes, if the dedicated LB **IP is unchanged** | Gone with Platform |
| Dedicated LB Service / EXTERNAL-IP | Yes (in-place patch). Deleting and recreating the Service can allocate a new IP; users re-login | Gone with Platform |
| `mlpipeline-minio-artifact` | Yes (Pipelines chart owns it; syncer recopies into profile nses) | Gone with Pipelines |
| Istio `istio.io/rev` on nses | Yes (syncer, not Helm). Syncer **rollout restart**s only when the label is missing, not on every reconcile | Labels remain on the Namespace objects |
| Profile namespaces / user files in them | Yes | Profiles listed in Platform values are deleted if you remove them from that list |
| MySQL + SeaweedFS **data** | Yes (PVCs) | **Kept** (`helm.sh/resource-policy: keep` on the two PVCs) |

Do not Disable/re-Enable Pipelines to "fix" a glitch if you care about runs and artifacts. After an uninstall, the PVCs stay; a later Enable may fail until Helm adopts them or you delete the PVCs for a true wipe.

### What is not stripped on upgrade

Dedicated gateway Deployment/Service, catch-all VirtualService, oauth2-proxy, and the secret-syncer Deployment stay in the charts. A normal Helm upgrade does not delete them. The old `namespace.yaml` that tried to own `Namespace/kubeflow` is gone on purpose so Flux `createNamespace` and the syncer labels do not fight.

### Storage (two 20Gi RWO PVCs in `kubeflow`)

- `mysql-pv-claim` — Pipelines metadata DB  
- `seaweedfs-pvc` — pipeline artifacts  

Default size is Helm values (NKP **configOverrides**):

```yaml
storage:
  mysql: 20Gi
  seaweedfs: 20Gi
```

**Grow later** (do not only `kubectl patch`; Flux would keep wanting the old size):

1. StorageClass must allow it: `kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{" allowVolumeExpansion="}{.allowVolumeExpansion}{"\n"}{end}'`
2. Set the same larger size in Pipelines `configOverrides` (example `50Gi` for both).
3. Wait until `kubectl -n kubeflow get pvc` shows the new request. If the filesystem does not expand on its own: `kubectl -n kubeflow rollout restart deploy mysql seaweedfs`

Kubernetes will not let you shrink. Do not set a smaller size than the live PVC.

### If you re-bake Pipelines

`just bake kubeflow-pipelines` regenerates `values.yaml` from the workload list only. Re-add the `storage:` block above. The PVC `keep` annotation and `dig` size templates are in `scripts/bake-apps.yaml` overlay injections so they come back.

## 6. Apply this commit on another clone

Patch (generated next to the catalog clone):

`/Users/snimar/Workplace/agent-sandbox/kubeflow-platform-automation.patch`

```bash
cd nkp-ai-applications-catalog
git checkout snimar/kubeflow-multiuser-dedicated-lb
git apply /Users/snimar/Workplace/agent-sandbox/kubeflow-platform-automation.patch
# or: git am < the format-patch file if you use that
```

Delete this file when the cluster is on the new OCI charts.
