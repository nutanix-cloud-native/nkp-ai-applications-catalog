# AMD Resource Manager 2.0.0

This document contains operational and implementation details for maintainers
and users of the NKP catalog package. Catalog-facing information is maintained
in `metadata.yaml`.

## Current Scope

This release supports **all mode** only. It installs the AMD Resource Manager
(AIRM) management plane and a local agent on the same cluster.

Management-only and remote-agent deployments are not implemented by this
catalog version. The catalog also does not currently install the Kaiwo or AIM
Engine controllers; it installs only the API prerequisites required by the
AIRM agent.

The primary workloads are installed in the `airm` namespace. Keycloak is
installed in the `keycloak` namespace. The Gateway and orchestration resources
are managed from the catalog release namespace.

## OCI Sources

The catalog entry uses a Flux `OCIRepository` and `HelmRelease` to install the
local `amd-resource-manager` orchestration chart. The exact repository and tag
are pinned in `helmrelease/helmrelease.yaml`.

The orchestration chart then deploys the following AIRM 2.0.0 charts from OCI
registries:

- `amdenterpriseai/airm-api-chart`
- `amdenterpriseai/airm-agent-chart`
- `amdenterpriseai/airm-cnpg-chart`
- `amdenterpriseai/airm-rabbitmq-chart`

Chart locations, image versions, tool images, and supporting component versions
are maintained in `charts/amd-resource-manager/2.0.0/values.yaml`.

## Gateway API CRDs

AIRM requires the Gateway API CRDs (`gateway.networking.k8s.io`) to be installed
before this application. This application does not install, upgrade, or manage
them. The `00-preflight` stage fails if the required CRDs, or
`BackendTLSPolicy/v1` served as the storage version, are missing.

NKP 2.20.0 includes the `gateway-api-crds` platform application, which provides
the standard channel at v1.4.0, including `BackendTLSPolicy/v1`. This is
sufficient for AIRM and Traefik.

Two sources provide these CRDs, and only one can own them on a cluster:

- **NKP `gateway-api-crds` platform application:** standard channel, v1.4.0.
  Sufficient for Traefik and AIRM.
- **Envoy Gateway NAI:** experimental channel, v1.5.1. Also provides
  `BackendTLSPolicy/v1` and experimental CRDs (`ListenerSet`, `TCPRoute`,
  `TLSRoute`, `UDPRoute`).

Do not install both on the same cluster. The `safe-upgrades`
ValidatingAdmissionPolicy shipped with Envoy Gateway NAI prevents the platform
standard CRDs and the Envoy experimental CRDs from coexisting, so an install or
upgrade can fail with a validation error.

Verify before installing AIRM:

```bash
kubectl get crd gatewayclasses.gateway.networking.k8s.io gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io backendtlspolicies.gateway.networking.k8s.io
kubectl get crd backendtlspolicies.gateway.networking.k8s.io -o jsonpath='{.spec.versions[?(@.storage==true)].name}'
```

The second command should print `v1`.

## Staged Reconciliation

The orchestration chart renders an ordered set of Flux Kustomizations. Each
stage has explicit dependencies and health checks, so a failed prerequisite
prevents later stages from running.

The current stage sequence is:

1. `00-preflight` discovers the domain, StorageClass, and Prometheus endpoint,
   verifies required platform services, and verifies the platform Gateway API
   CRDs, including `BackendTLSPolicy/v1` served as the storage version.
2. `01-secrets` generates and validates the Kubernetes Secrets needed by AIRM,
   PostgreSQL, RabbitMQ, and Keycloak.
3. `02-gateway` creates the AIRM Gateway. It does not install or upgrade Gateway
   API CRDs. See [Gateway API CRDs](#gateway-api-crds).
4. `03a-keycloak` installs Keycloak, and `03b-keycloak-config` configures the AIRM realm, clients, and users.
5. `04-storage` validates and prepares the selected StorageClass.
6. `05a-operators` applies the vendored RabbitMQ Cluster Operator manifest and
   waits for its Deployment to be Ready.
7. `05b-infrastructure` deploys PostgreSQL and RabbitMQ.
8. `06-rabbitmq-config` configures the RabbitMQ resources used by AIRM.
9. `07a-agent-crd-definitions` applies the Kaiwo and AIM Engine CRDs, with pruning and force disabled.
10. `07b-kaiwo-queue-seed` creates the `KaiwoQueueConfig/kaiwo` seed if it is absent.
11. `08-management` deploys the AIRM API and UI.
12. `09-bootstrap` registers the local cluster with AIRM.
13. `10-identity-sync` reconciles the registered cluster's RabbitMQ identity.
14. `11-gateway-tls` creates the self-signed Gateway certificate and routes.
15. `12-agent` deploys the local AIRM agent.
16. `13-post-install` verifies the completed installation and emits an access
    summary.

The parent HelmRelease enables drift detection. If a rendered stage
Kustomization is manually deleted or modified, helm-controller restores it
during a subsequent HelmRelease reconciliation.

To inspect the rollout, list the stage resources in the catalog release
namespace:

```bash
kubectl get kustomizations.kustomize.toolkit.fluxcd.io \
  -n <catalog-release-namespace>
kubectl get jobs -n <catalog-release-namespace>
kubectl get helmreleases.helm.toolkit.fluxcd.io -A
```

For a failed stage, inspect its Kustomization and the associated Job or
HelmRelease before retrying:

```bash
kubectl describe kustomization <stage-name> \
  -n <catalog-release-namespace>
kubectl logs job/<job-name> -n <job-namespace>
```

## Release Artifact Integrity

The Kaiwo and AIM Engine CRDs are vendored in
`applications/amd-resource-manager/2.0.0/helmrelease/stages/07a-agent-crd-definitions/`
and applied by stage `07a-agent-crd-definitions`. Each file records its upstream
source URL, release version, and SHA-256 digest in its header. No release
artifact is downloaded at install time.

Stage `07a` runs with pruning and force disabled, so removing or changing the stage never
deletes the CRDs or the custom resources stored under them. A change that would need a
CRD replaced fails the stage instead of Flux deleting and recreating it. The CRDs are not part
of the Helm chart, so chart upgrades don't touch them. A new catalog version that
changes a CRD is applied when stage `07a` reconciles. A change that removes a
stored version is rejected by the API server, which holds stage `07b` and every
later stage until the change is resolved.

Stage `07b-kaiwo-queue-seed` runs only after stage `07a` is Ready, so the CRDs are
already Established. It creates the cluster-scoped `KaiwoQueueConfig/kaiwo` seed
object only if it is absent. An existing seed is never modified. Transient API
errors are retried a bounded number of times, and authorization failures fail
the stage immediately.

The RabbitMQ Cluster Operator manifest is vendored at
`applications/amd-resource-manager/2.0.0/helmrelease/stages/05a-operators/rabbitmq-cluster-operator.yaml`.
Stage 05a applies it directly as a Flux-managed resource, and Flux gates the stage on
the `rabbitmq-cluster-operator` Deployment in `rabbitmq-system`. Flux owns this operator:
it applies the vendored version on each reconcile, so an operator installed outside
this catalog is upgraded to the vendored version. Stage 05a runs with pruning and force
disabled, so removing the stage never deletes the operator CRDs or the RabbitMQ clusters,
and a change that would need the operator replaced fails instead of being recreated. The
manifest's provenance header records the upstream URL and SHA-256 digest. Upgrading
requires re-vendoring the manifest and updating that header.

No release artifact is downloaded at install time. Vendored files are reviewed
in git, and their provenance headers record the upstream source and digest.

### Kaiwo and AIM API coverage

The current release uses the Kaiwo CRDs to provide the Kubernetes API types
expected by the AIRM agent. It also ensures the cluster-scoped `KaiwoQueueConfig/kaiwo` object exists. Stage
07 creates it only when it is absent and never modifies an existing object. AIRM
uses it to record project quota and resource-allocation state. Quota changes can be inspected with:

```bash
kubectl get kaiwoqueueconfig kaiwo -o yaml
```

The Kaiwo and AIM Engine controllers are not part of this catalog release.
Consequently, the CRDs accept and expose custom-resource state, but they do not
by themselves reconcile `KaiwoJob`, `KaiwoService`, or `AIMService` resources
into running workloads. Workload scheduling, job execution, and inference
service reconciliation require the corresponding controllers and are planned
for separate integration and validation.

## Access and Credentials

The default endpoints use the domain selected by preflight discovery:

- AIRM UI: `https://airmui.<domain>`
- AIRM API: `https://airmapi.<domain>`
- Keycloak: `https://kc.<domain>`

The Gateway currently uses a self-signed TLS certificate, so browsers and API
clients will report a trust warning unless that certificate is trusted
explicitly.

### Set the initial AIRM username (fresh install only)

Use this only when installing the application on a cluster where AIRM is not
yet installed. The default username is `devuser`, and the login is
`<username>@<domain>`.

Create a ConfigMap in the `kommander` namespace that sets `airm.username`:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: amd-resource-manager-<username>-username
  namespace: kommander
data:
  values.yaml: |
    airm:
      username: <username>
EOF
```

Create the AppDeployment with the `nkp` CLI and reference that ConfigMap with
`--add-cluster-config-overrides`:

```bash
nkp create appdeployment <app-deployment-name> \
  --app amd-resource-manager-2.0.0 \
  --clusters <cluster-name> \
  --add-cluster-config-overrides <cluster-name>:amd-resource-manager-<username>-username \
  --workspace <workspace-name>
```

Replace `<username>`, `<app-deployment-name>`, `<cluster-name>`, and
`<workspace-name>` with your values. The username must be 1-64 characters: lowercase letters, digits,
dots, dashes, or underscores, and it must start with a letter or digit.

The username is used only when stage `01-secrets` creates
`airm-user-credentials` during this first installation. Do not use this
override on a cluster where AIRM is already installed.

### Retrieve the AIRM UI credentials

Stage `01-secrets` creates the initial AIRM user in the
`airm-user-credentials` Secret. Run these commands to retrieve the username and
password used to log in at `https://airmui.<domain>`:

```bash
kubectl get secret airm-user-credentials -n airm \
  -o jsonpath='{.data.USER_EMAIL}' | base64 -d; echo
kubectl get secret airm-user-credentials -n airm \
  -o jsonpath='{.data.USER_PASSWORD}' | base64 -d; echo
```

Keycloak administrator credentials are stored in `keycloak-kcadmin`:

```bash
kubectl get secret keycloak-kcadmin -n keycloak \
  -o jsonpath='{.data.username}' | base64 -d; echo
kubectl get secret keycloak-kcadmin -n keycloak \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

The post-install Job does not write usernames or passwords to its logs. Its
summary prints only the URLs and the `kubectl` commands for reading the Secrets.
Retrieve credentials by reading the Secrets directly, as an intentional operator
action.

Existing generated Secrets are preserved during normal stage retries where
possible. Deleting them can rotate credentials and cause dependent components
to become inconsistent.

### Recover a lost or deleted Secret

If a generated Secret is missing or lost, or AIRM fails with a credential
error, follow [SECRET-RECOVERY.md](SECRET-RECOVERY.md). It explains how to
restore each Secret from a backup, or recover it by hand, and which component
to restart afterward.

## External Secrets

Treat infrastructure secrets and project secrets as separate paths.

Stage `01-secrets` creates AIRM's own infrastructure credentials
(PostgreSQL, RabbitMQ, Keycloak, and the initial AIRM user) as native
Kubernetes Secrets. That path does not use External Secrets Operator.

Project External Secrets are an optional AIRM feature. A project secret is
a scope/assignment concept in the AIRM UI, not a separate `ProjectSecret`
Kubernetes kind. The validated NKP flow is:

1. External Secrets Operator is installed and Ready.
2. An administrator creates a Ready `ClusterSecretStore`.
3. A user creates an External Secret from a project's **Secrets** tab.
4. AIRM creates an `ExternalSecret` (`external-secrets.io/v1`) in the
   project namespace.
5. ESO syncs the remote value into a Kubernetes `Secret`.
6. Project workloads consume that Kubernetes Secret.

`external-secrets` is listed as a soft dependency in `metadata.yaml`. AIRM
still installs and runs without it; native Kubernetes project secrets
remain available. Enabling External Secrets Operator alone is not enough:
operators must also provide a Ready `ClusterSecretStore` and a reachable
backend (or a lab fake provider).

The catalog disables the upstream configure Job's demo MinIO setup. That
demo is only one optional consumer of External Secrets; disabling it does
not remove the general project-secret feature. See AMD's
[Secrets Overview](https://enterprise-ai.docs.amd.com/en/latest/resource-manager/secrets/overview.html)
and `EXTERNAL-SECRETS.md`.

## Current Feature Coverage

- This release supports the combined management-plane and local-agent
  deployment provided by all mode.
- Management-only and remote-agent modes are reserved for future catalog
  versions.
- Project and quota state is supported through the AIRM agent and
  `KaiwoQueueConfig`; full Kaiwo and AIM workload reconciliation requires their
  corresponding controllers.
- The optional upstream demo project and MinIO setup are not enabled.
- Project External Secrets are optional and validated through the AIRM UI
  when External Secrets Operator and a Ready ClusterSecretStore are present.
- Gateway access currently uses a self-signed certificate.

## Uninstall and Clean Reinstall

Removing or reinstalling this application does not clear its state. The following survive:

| Item | Why it survives |
|---|---|
| Kaiwo and AIM Engine CRDs, and every custom resource stored under them | Stage `07a-agent-crd-definitions` uses `prune: false` and `force: false` |
| `KaiwoQueueConfig/kaiwo` seed and its quota state | Created by a script in stage `07b`, not managed by Flux. It is never modified, and AIRM adds a finalizer to it. |
| AIRM PostgreSQL (CloudNativePG) data and the AIRM database | Persistent volume claims in the `airm` namespace |
| RabbitMQ data, vhosts, users, and queues | Persistent volume claims in the `airm` namespace |
| Keycloak realm, users, and data | Persistent volume claims in the `keycloak` namespace |
| Generated Secrets: `airm-user-credentials`, `airm-rabbitmq-admin`, `airm-rabbitmq-common-vhost-user`, `airm-cnpg-user`, `airm-cnpg-superuser`, `airm-secrets-airm`, `keycloak-kcadmin` | Stage `01-secrets` keeps existing Secrets on retries |
| RabbitMQ Cluster Operator CRDs (`rabbitmq.com`) | Stage `05a-operators` uses `prune: false` and `force: false` |
| Project namespaces (labelled `airm.silogen.ai/project-id`) | AIRM creates them, not Flux, so removing the AppDeployment doesn't remove them. A new project with the same name fails with `namespace already exists`. |
| HelmReleases `airm-keycloak` (stage `03a-keycloak`), `airm-infra-cnpg` and `airm-infra-rabbitmq` (stage `05b-infrastructure`), and their `sh.helm.release.v1.*` Secrets in the release namespace | Those stages use `prune: false`, so removing the AppDeployment leaves these objects behind. Helm still records them as installed, so a reinstall reports `in sync` and doesn't recreate the workloads. |

A normal reinstall works. When the AIRM database, the `airm-rabbitmq-common-vhost-user` Secret, and the registration are all still present, stage `09-bootstrap` finds the existing registration and exits without changes.

### Reset to a clean state

These steps destroy data. Run them in order, and only on a cluster where no other workload depends on AIRM. Check each step's output before you move on.

The order matters. The seed and project cleanup need the AIRM API, and deleting the AppDeployment or `airm-management` takes that API down.

1. **Delete the projects while AIRM is running.** AIRM creates one namespace per project, labelled `airm.silogen.ai/project-id`. Delete the projects in the AIRM UI or API first, then check whether any namespace is left over:

   ```
   kubectl get ns -l airm.silogen.ai/project-id
   kubectl delete ns -l airm.silogen.ai/project-id
   ```

   Check first that each namespace has no workloads you need. A leftover project namespace makes AIRM fail the next project with the same name with `namespaces "<name>" already exists`.

2. **Delete the seed while AIRM is running.** This lets AIRM remove its finalizer. If the seed stays in `Terminating`, check for the `airm.silogen.ai/kaiwoqueueconfig-finalizer` finalizer before you do anything else.

   ```
   kubectl delete kaiwoqueueconfig kaiwo
   ```

3. **Delete the AppDeployment.** The AppDeployment owns the catalog HelmRelease and the stage Kustomizations. Deleting only those objects doesn't work, because the AppDeployment recreates them. Find its name first, then delete it:

   ```
   kubectl get appdeployment -n kommander | grep -E 'amd|airm'
   kubectl delete appdeployment <name> -n kommander
   ```

   Then check that nothing has come back:

   ```
   kubectl get kustomization,helmrelease -n kommander | grep -E 'amd-resource|airm|keycloak'
   ```

4. **Delete the stage HelmReleases and their Helm release records.** Stages with `prune: false` leave these behind, and a stale record makes the next install report `in sync` without recreating the workloads.

   ```
   kubectl delete helmrelease airm-infra-cnpg airm-infra-rabbitmq airm-keycloak airm-management airm-agent -n kommander --ignore-not-found
   kubectl delete secret -n kommander sh.helm.release.v1.airm-infra-cnpg.v1 sh.helm.release.v1.airm-infra-rabbitmq.v1 sh.helm.release.v1.keycloak.v1 sh.helm.release.v1.airm.v1 sh.helm.release.v1.airm-agent.v1 --ignore-not-found
   kubectl get secret -n kommander | grep -E 'sh\.helm\.release\.v1\.(airm|keycloak)'
   ```

   Deleting `airm-infra-cnpg` and `airm-infra-rabbitmq` uninstalls the CloudNativePG and RabbitMQ clusters. Their pods can take about five minutes to shut down gracefully, so wait for them to finish before the next step.

5. **Delete the `airm` and `keycloak` namespaces.** This removes the AIRM database, RabbitMQ data, and Keycloak realm, along with the Secrets listed above.

   ```
   kubectl delete ns airm keycloak
   ```

   If a namespace stays `Terminating`, see [Clearing a stuck namespace](#clearing-a-stuck-namespace) below.

6. **Delete the stage Jobs and leftover objects in the release namespace.** List the names first, then delete them one at a time:

   ```
   kubectl get job -n kommander --no-headers -o custom-columns=NAME:.metadata.name | grep '^airm-'
   kubectl delete job <name> -n kommander
   kubectl delete configmap airm-discovered -n kommander --ignore-not-found
   kubectl delete secret airm-gateway-tls -n kommander --ignore-not-found
   ```

7. **Delete the Kaiwo and AIM Engine CRDs.** This also deletes every `KaiwoJob`, `KaiwoService`, `KaiwoConfig`, `KaiwoQueueConfig`, and AIM resource. List the names first. Then delete them, after confirming that no other workload uses them:

   ```
   kubectl get crd | grep -E 'kaiwo\.silogen\.ai|aim\.eai\.amd\.com'
   ```

8. **Optional: reinstall the RabbitMQ Cluster Operator.** Delete the `rabbitmq-system` namespace and the `rabbitmq.com` CRDs. This deletes every `RabbitmqCluster`. Don't delete CloudNativePG or other NKP platform CRDs, since this application doesn't own them. The `rabbitmq-system` namespace is also stuck on the AIRM finalizer, so if it stays `Terminating`, see [Clearing a stuck namespace](#clearing-a-stuck-namespace).

9. **Remove the AIRM gateway and catalog sources.** The `airm-https` Gateway and the `airm-*` and `amd-resource-manager-*` OCIRepositories are left from earlier installs. Remove them if you want a fully clean catalog source:

   ```
   kubectl get gateway -n kommander airm-https
   kubectl delete gateway -n kommander airm-https --ignore-not-found
   kubectl get ocirepository -n kommander | grep -E 'airm|amd-resource-manager'
   ```

10. **Reinstall the application.**

#### Clearing a stuck namespace

AIRM puts `airm.silogen.ai/namespace-finalizer` on its namespaces. Once the AIRM API is gone, nothing removes that finalizer, so the namespace stays `Terminating`.

Only clear the finalizer when the namespace is empty. Check for leftover objects first, including PVCs and PVs. Removing the finalizer while pods or PVCs still exist leaves them orphaned.

```
kubectl get ns <name> -o jsonpath='{.metadata.finalizers}{"\n"}'
kubectl get pods,pvc,svc,secret,configmap,deploy,statefulset -n <name>
kubectl get pv | grep <name>
kubectl patch ns <name> --type=merge -p '{"metadata":{"finalizers":null}}'
```

Only clear it when all the `get` commands above return nothing.

### Verify a clean state

Run these before reinstalling. Each command should return nothing, except the last line, which should report that the server doesn't have that resource type.

```
kubectl get appdeployment -n kommander | grep -E 'amd|airm'
kubectl get kustomization,helmrelease -n kommander | grep -E 'amd-resource|airm|keycloak'
kubectl get secret -n kommander | grep -E 'sh\.helm\.release\.v1\.(airm|keycloak|amd-resource)'
kubectl get ns | grep -E '^(airm|keycloak|rabbitmq-system)'
kubectl get ns -l airm.silogen.ai/project-id
kubectl get pv | grep -E 'airm|keycloak'
kubectl get gateway -n kommander airm-https
kubectl get ocirepository -n kommander | grep -E 'airm|amd-resource-manager'
kubectl get crd | grep -E 'kaiwo\.silogen\.ai|aim\.eai\.amd\.com'
kubectl get kaiwoqueueconfig
```

### Rerun a failed stage Job

Each stage runs one Kubernetes Job (`airm-*`) in the release namespace. Its pod retries up to three times within `activeDeadlineSeconds`. When those retries run out, the Job stays `Failed`. Flux doesn't rerun a failed Job unless its spec changes, so the stage waits.

If a stage stays stuck on a Job that has failed for good, check its logs, fix the cause (for example, a Keycloak or RabbitMQ that wasn't ready), and then delete the Job:

```
kubectl get job -n kommander | grep airm-
kubectl logs -n kommander job/<job-name>
kubectl delete job <job-name> -n kommander
```

Flux recreates a deleted stage Job the next time its stage Kustomization reconciles. In testing, a deleted Job that had already completed was recreated within seconds of the reconcile. Recovery from a Job that failed for good, and the timing of the automatic one-minute reconcile, are not covered by that test. To watch the Job and its stage, run `kubectl get kustomization -n kommander` and `kubectl get job -n kommander`.

Don't delete a Job that is still running. A `Complete` Job doesn't need deleting, since its TTL removes it after 24 hours.

## Links

- [AMD Resource Manager documentation](https://enterprise-ai.docs.amd.com/en/v2.2.2/resource-manager/overview.html)
- [AMD Enterprise AI Suite 2.2.2 release notes](https://enterprise-ai.docs.amd.com/en/v2.2.2/release-notes.html)
