# MLflow catalog integration

Workspace-scoped NKP catalog app. Catalog/chart version `1.11.4`, image
`burakince/mlflow:3.15.1` (MLflow 3.15.1 — the chart version and the app version differ).

One instance per cluster, always in namespace `mlflow`. `allowMultipleInstances: false`.

Default install: ClusterIP behind Traefik at `/nkp/mlflow`, SQLite metadata and proxied artifacts on one 10Gi PVC, **unauthenticated**. External PostgreSQL and S3 supported via config override.

## Layout

```
NKP catalog entry 1.11.4
  → Flux HelmRelease
    → Nutanix OCI chart mlflow:1.11.4
      → Deployment/Service/Ingress (chart)
      → SQLite + artifacts on PVC mlflow-data
```

## Chart

Mirrored unchanged from `https://community-charts.github.io/helm-charts`:

```bash
just mirror-chart-from-repo https://community-charts.github.io/helm-charts mlflow 1.11.4
```

Consumed as `oci://ghcr.io/nutanix-cloud-native/charts/mlflow:1.11.4`.

Images: `burakince/mlflow:3.15.1` always; `library/busybox:1.38.0` (×2) only with external database or chart auth. The busybox images don't render by default, so image discovery misses them — they must be listed in `helmrelease/extra-images.txt`.

## Catalog manifests

`applications/mlflow/1.11.4/`

| File | Role |
|---|---|
| `metadata.yaml` | NKP UI metadata, scope, warnings |
| `kustomization.yaml` | Points at Flux Kustomization |
| `helmrelease.yaml` | Flux Kustomization → `./helmrelease` |
| `.bloodhound.yml` | Schema validation |
| `helmrelease/namespace.yaml` | Fixed `mlflow` namespace |
| `helmrelease/pvc.yaml` | `mlflow-data` 10Gi RWO in `mlflow` |
| `helmrelease/cm.yaml` | Chart values |
| `helmrelease/mlflow-ui-dashboard-cm.yaml` | Launch button |
| `helmrelease/helmrelease.yaml` | OCIRepository + HelmRelease + probe postRenderer |
| `helmrelease/kustomization.yaml` | Lists the above |

Two deviations from chart-native config, both necessary:

- **PVC is a catalog manifest** — the chart has no persistence values.
- **`postRenderers` patches the probe paths** — see [Known limitations](#known-limitations).

Objects land in two namespaces: `${releaseNamespace}` (the workspace namespace, where Flux and NKP objects live) and `mlflow` (the workload). The PVC hardcodes `namespace: mlflow` because it must sit alongside the pod that mounts it.

## Storage

One PVC at `/mlflow/data` holds both stores: SQLite (`mlflow.db`) for metadata, and
`mlartifacts/` for logged files.

**Survives** pod restarts, reschedules, node drains, and upgrades. **Deleted on uninstall**
along with the namespace — there are no retention annotations, and retaining the PVC would require exempting the namespace from pruning, leaving orphaned storage invisible in the UI. Use external stores if durability across uninstall matters.

Four values are load-bearing — don't remove them:

| Value | Why |
|---|---|
| `strategy: Recreate` | RWO volume; chart's `RollingUpdate` default deadlocks every upgrade |
| `defaultSqlitePath: /mlflow/data/mlflow.db` | Chart default is `":memory:"`, which loses writes |
| `proxiedArtifactStorage: true` | Without it clients try to write the server's path locally |
| `extraVolumeMounts` at `/mlflow/data` | `readOnlyRootFilesystem: true` — nothing else is writable |

Consequences: single replica permanently, SQLite write-concurrency limits, fixed capacity
(`storageClassName` unset, so expansion depends on the cluster default), and no artifact garbage collection (`mlflow gc` is manual).

## Access

Traefik Ingress at `/nkp/mlflow`, class `kommander-traefik`, no host restriction, **no prefix stripping**.

Three values must agree: the ingress path, `extraArgs.staticPrefix`, and the probe path in the `postRenderers` patch.

## Configuration overrides

Catalog defaults are in `cm.yaml`. Users don't edit catalog files — NKP appends a second `valuesFrom` at install time.

> **Use the cluster override for external stores.** A workspace value fans out to every cluster,
> pointing multiple MLflow instances at one database — concurrent schema migrations against one
> schema, and runs silently mixed across clusters.

## Production configuration

PostgreSQL for metadata, S3-compatible storage for artifacts. Neither is created or managed by this entry, and uninstall doesn't touch them. Artifacts can't go in PostgreSQL. MLflow has no such option.

**Prerequisites:** a reachable PostgreSQL with the database already created and a user holding DDL rights (MLflow creates its schema, not the database); an existing S3 bucket; and two Secrets
in the `mlflow` namespace:

```bash
kubectl create secret generic mlflow-db-credentials -n mlflow \
  --from-literal=username=<user> --from-literal=password=<password>

kubectl create secret generic mlflow-s3-credentials -n mlflow \
  --from-literal=AWS_ACCESS_KEY_ID=<key> --from-literal=AWS_SECRET_ACCESS_KEY=<secret>
```

Modify accordingly and paste into the **cluster** override editor:

```yaml
backendStore:
  databaseMigration: true
  databaseConnectionCheck: true
  postgres:
    enabled: true
    host: postgres.example.com # modify
    port: 5432
    database: mlflow
  existingDatabaseSecret:
    name: mlflow-db-credentials

artifactRoot:
  proxiedArtifactStorage: true
  s3:
    enabled: true
    bucket: mlflow
    path: artifacts
    existingSecret:
      name: mlflow-s3-credentials

# Non-AWS endpoints only
extraEnvVars:
  MLFLOW_S3_ENDPOINT_URL: http://minio.example.com:9000 # modify
```

Either store can be configured independently. Note that **switching stores does not migrate data** — the UI will appear empty afterwards, and the PVC remains provisioned but unused.
Clearing the override reverts cleanly to SQLite.

## Authentication

**Unauthenticated.** Anyone who can reach the Traefik endpoint has full read/write.

**Why SSO isn't enabled:** NKP forward-auth is one annotation and works for browsers — it was implemented and verified. It's not enabled because it breaks programmatic access, which is MLflow's primary interface.


## Uninstall

Deletes the `mlflow` namespace and everything in it, including the PVC and all data. External stores are untouched.


## Known limitations

**Probe paths are patched, not configured.** The chart hardcodes both probes to `/health` and exposes no path value. With `--static-prefix`, that path 404s and the pod never becomes Ready.
The `postRenderers` patch sets `/nkp/mlflow/health` — **if the ingress path changes, this must change with it.** Same shape as
[gitlab#6090](https://gitlab.com/gitlab-org/charts/gitlab/-/issues/6090).
