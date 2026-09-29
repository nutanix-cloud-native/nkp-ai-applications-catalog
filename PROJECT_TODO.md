# NKP AI Applications Catalog — Project TODO

Persistent TODO list for catalog release. Use `just todo` to view, `just todo-add "task"` to add, `just todo-complete <pattern>` to mark complete.

---

## 1. Add latest versions for each existing app

Update all existing apps to their latest available versions.

**Existing apps:** agentgateway, coder, demo-full-rag, flowise, jupyterhub, kagent, katib, kserve, kubeflow-central-dashboard, kubeflow-model-registry, kubeflow-pipelines, milvus-operator, mlflow, ollama, open-webui, spark-operator, tensorboard-controller, training-operator, vllm, weaviate

- [ ] agentgateway
- [ ] coder
- [ ] demo-full-rag
- [ ] flowise
- [ ] jupyterhub
- [ ] kagent
- [ ] katib
- [ ] kserve
- [ ] kubeflow-central-dashboard
- [ ] kubeflow-model-registry
- [ ] kubeflow-pipelines
- [ ] milvus-operator
- [ ] mlflow
- [ ] ollama
- [ ] open-webui
- [ ] spark-operator
- [ ] tensorboard-controller
- [ ] training-operator
- [ ] vllm
- [ ] weaviate

---

## 2. Create test plan for each app

Create a test plan document per app. Test matrix:

- [ ] **Basic test matrix** — document baseline scenarios
- [ ] **Enable app on mgmt and/or workload** — verify install on management vs workload cluster
- [ ] **Edit app custom config** — workspace-level and cluster-specific config overrides
- [ ] **Edit app by deploying on one or more clusters** — multicluster deployment
- [ ] **Upgrade** — upgrade from previous version
- [ ] **Disable app** — uninstall/disable flow
- [ ] **Verify metadata.yaml and UI view** — overview correctness in NKP UI
- [ ] **Verify dependencies and requiredDependencies** — install order, dependency resolution
- [ ] **UI apps: verify all paths** — if app has UI, open and verify paths work

---

## 3. Add unit tests (catalog-apptests)

Add unit tests similar to [dm-nkp-gitops-app-catalog/catalog-apptests](https://github.com/deepak-muley/dm-nkp-gitops-app-catalog/tree/main/catalog-apptests).

- [ ] Create `catalog-apptests/` directory structure
- [ ] Port discovery, cluster, app, and suite logic for NKP AI catalog
- [ ] Integrate with CI (e.g. `just test` or `./catalog-workflow.sh test --catalog-apptests`)

---

## 4. Legal approval for Rapid Fort images

Get legal approval to finalize whether to use Rapid Fort images for open source app containers.

- [ ] Document current image sources
- [ ] Evaluate Rapid Fort image availability for catalog apps
- [ ] Legal review and approval
- [ ] Update manifests if approved

---

## 5. Make repo public

Make the repository public after testing is complete.

- [ ] Complete testing (see items 2, 3)
- [ ] Remove or sanitize any private/sensitive content
- [ ] Update visibility to public

---

## 6. Add new or missing apps (final release)

Add the following apps with their latest versions:

### Devtools

- [ ] JupyterHub (already present — verify latest)
- [ ] Flowise (already present — verify latest)
- [ ] Apache Zeppelin

### MLOps

- [ ] Kubeflow (kubeflow-* components already present — verify/consolidate)
- [ ] Mlflow (already present — verify latest)
- [ ] Ray

### VectorDB

- [ ] Milvus (milvus-operator present — verify/complete)
- [ ] Weaviate (already present — verify latest)
- [ ] Elastic

### Agentic

- [ ] LangGraph
- [ ] crewAI
- [ ] Sim

### NVIDIA

- [ ] NVIDIA NIM
- [ ] NVIDIA DOCA

---

## Quick reference

| Command | Description |
|---------|-------------|
| `just todo` | View this TODO file |
| `just todo-list` | List tasks (same as view) |
| `just todo-add "task"` | Append a new task to PROJECT_TODO.md |
| `just todo-complete <pattern>` | Mark a task complete (e.g. `just todo-complete agentgateway`) |
