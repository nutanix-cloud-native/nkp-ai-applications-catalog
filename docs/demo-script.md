# Demo Script: NKP Catalog Sample Apps

This script walks through demonstrating the **Demo Connector** and **Demo RAG** sample apps, which showcase catalog composability and dependency flow.

## Prerequisites

- NKP cluster with a workspace
- `kubectl` configured (or `KUBECONFIG` / `--kubeconfig` for workload cluster)
- `docker`, `helm`, `nkp` CLI
- Devbox (optional): `devbox shell` for reproducible env

## Step 1: Build and push demo app images and charts

The demo apps live in separate repos. Build and push from each:

```bash
# Demo Connector
cd /Users/deepak.muley/go/src/github.com/deepak-muley/nkp-demo-connector
docker login ghcr.io
helm registry login ghcr.io
make release VERSION=1.0.0

# Demo RAG
cd /Users/deepak.muley/go/src/github.com/deepak-muley/nkp-demo-rag
make release VERSION=1.0.0
```

This pushes:

- `ghcr.io/deepak-muley/demo-connector:1.0.0`
- `ghcr.io/deepak-muley/demo-rag:1.0.0`
- Helm charts to `oci://ghcr.io/deepak-muley/charts`

## Step 2: Validate and create catalog bundle

```bash
cd /Users/deepak.muley/go/src/github.com/nutanix-cloud-native/nkp-ai-applications-catalog

devbox shell   # optional
just login     # login to OCI registries
just validate  # validate catalog
just push-bundle v0.1.0 oci://ghcr.io/deepak-muley/nkp-ai-applications-catalog
```

The demo apps already reference `oci://ghcr.io/deepak-muley/charts` in their helmreleases, so no `CHART_REGISTRY` override is needed.

## Step 3: Deploy catalog to workspace

```bash
just add-to-cluster <workspace-name> v0.1.0 oci://ghcr.io/deepak-muley/nkp-ai-applications-catalog/nkp-ai-applications-catalog/collection
```

Remove `--dry-run` from the command if your justfile has it, or run the `nkp create catalog-collection` command directly without `--dry-run` to actually deploy.

## Step 4: Enable apps from NKP UI

1. **Enable Weaviate**  
   - Open the workspace in NKP UI  
   - Enable **Weaviate**  
   - Wait until it is ready (e.g. pods running in `weaviate` namespace)

2. **Enable Demo Connector**  
   - Enable **Demo Connector (Sample)**  
   - Wait for it to be ready (post-install Job patches the Launch URL)  
   - Click the **Launch** button in the NKP UI, or get the URL manually:
     ```bash
     kubectl get svc -n demo-connector demo-connector -o jsonpath='http://{.status.loadBalancer.ingress[0].ip}:80'
     ```
   - You should see: **Weaviate: Connected**

3. **Enable Demo RAG**  
   - Enable **Demo RAG (Sample)**  
   - Wait for it to be ready  
   - Click the **Launch** button, or:
     ```bash
     kubectl get svc -n demo-rag demo-rag -o jsonpath='http://{.status.loadBalancer.ingress[0].ip}:80'
     ```
   - Try queries: "NKP", "Weaviate", "RAG"  
   - You should see relevant document snippets

## Step 5: Verify via kubectl (optional)

```bash
# Check Weaviate
kubectl get pods -n weaviate

# Check Demo Connector
kubectl get pods -n demo-connector
kubectl get svc -n demo-connector

# Check Demo RAG
kubectl get pods -n demo-rag
kubectl get svc -n demo-rag
```

## Demo talking points

1. **Launch button** — Both apps expose a web UI; the NKP **Launch** button opens it after the post-install Job discovers the LoadBalancer URL.
2. **Dependency flow** — Demo Connector and Demo RAG declare Weaviate as a required dependency; the UI guides users to enable it first.
3. **In-cluster discovery** — Apps use Kubernetes DNS (`weaviate.weaviate.svc.cluster.local`) with no manual configuration.
4. **Composability** — Multiple apps share Weaviate in the same workspace.
5. **GitOps** — All manifests are declarative; Flux reconciles state.

## Troubleshooting

| Issue | Check |
|-------|-------|
| Launch button missing or broken | Post-install Job may still be running. Check: `kubectl get jobs -n <workspace-namespace>` and `kubectl get cm demo-connector-ui -n <workspace-namespace> -o yaml` for `dashboardLink` |
| Demo Connector shows "Not reachable" | Weaviate must be enabled and ready first. Verify: `kubectl get pods -n weaviate` |
| Demo RAG returns no results | Weaviate URL may be wrong. Ensure both apps are in the same workspace. |
| Chart not found | Ensure `make release` was run and charts were pushed to `oci://ghcr.io/deepak-muley/charts` |
| Image pull errors | Ensure images are public or imagePullSecrets are configured for `ghcr.io/deepak-muley` |
