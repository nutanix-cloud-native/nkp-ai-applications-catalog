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

## Staged Reconciliation

The orchestration chart renders an ordered set of Flux Kustomizations. Each
stage has explicit dependencies and health checks, so a failed prerequisite
prevents later stages from running.

The current stage sequence is:

1. `00-preflight` discovers the domain, StorageClass, and Prometheus endpoint,
   and verifies required platform services.
2. `01-secrets` generates and validates the Kubernetes Secrets needed by AIRM,
   PostgreSQL, RabbitMQ, and Keycloak.
3. `02-gateway` validates Gateway API support and creates the AIRM Gateway.
4. `03-keycloak` installs and configures Keycloak.
5. `04-storage` validates and prepares the selected StorageClass.
6. `05a-operators` applies the vendored RabbitMQ Cluster Operator manifest and
   waits for its Deployment to be Ready.
7. `05b-infrastructure` deploys PostgreSQL and RabbitMQ.
8. `06-rabbitmq-config` configures the RabbitMQ resources used by AIRM.
9. `07a-agent-crd-definitions` applies the Kaiwo and AIM Engine CRDs, with pruning disabled.
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
source URL, release version, and SHA-256 digest in its header. The catalog no
longer downloads these artifacts at install time.

Stage `07a` runs with pruning disabled, so removing or changing the stage never
deletes the CRDs or the custom resources stored under them. The CRDs are not part
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
this catalog is upgraded to the vendored version. Stage 05a runs with pruning disabled,
so removing the stage never deletes the operator CRDs or the RabbitMQ clusters. The
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

The post-install Job currently includes these credentials in its completion
summary. Because Kubernetes logs may be retained or collected centrally,
access to the Job logs must be restricted. Direct Secret retrieval should be
used as an intentional, audited operator action.

Existing generated Secrets are preserved during normal stage retries where
possible. Deleting them can rotate credentials and cause dependent components
to become inconsistent.

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

## Updating the Catalog Entry

When changing a chart source, release artifact, or image:

1. Update its pinned version or tag.
2. Re-vendor the changed artifact and update its provenance header. For Kaiwo or AIM Engine, that is the files in `stages/07a-agent-crd-definitions/`. For RabbitMQ, it is `stages/05a-operators/rabbitmq-cluster-operator.yaml`. The `kaiwo`, `aimEngine`, and `rabbitmqOperator` versions in `values.yaml` are documentation only.
3. Render and inspect the orchestration chart.
4. Validate the catalog repository.
5. Build a fresh catalog bundle and publish it under a new immutable tag.
6. Reconcile the NKP catalog collection and verify every stage becomes Ready.

## Uninstall and Clean Reinstall

Removing or reinstalling this application does not clear its state. The following survive:

| Item | Why it survives |
|---|---|
| Kaiwo and AIM Engine CRDs, and every custom resource stored under them | Stage `07a-agent-crd-definitions` uses `prune: false` |
| `KaiwoQueueConfig/kaiwo` seed and its quota state | Created by a script in stage `07b`, not managed by Flux. It is never modified, and AIRM adds a finalizer to it. |
| AIRM PostgreSQL (CloudNativePG) data and the AIRM database | Persistent volume claims in the `airm` namespace |
| RabbitMQ data, vhosts, users, and queues | Persistent volume claims in the `airm` namespace |
| Keycloak realm, users, and data | Persistent volume claims in the `keycloak` namespace |
| Generated Secrets: `airm-user-credentials`, `airm-rabbitmq-admin`, `airm-rabbitmq-common-vhost-user`, `airm-cnpg-user`, `airm-cnpg-superuser`, `airm-secrets-airm`, `keycloak-kcadmin` | Stage `01-secrets` keeps existing Secrets on retries |
| RabbitMQ Cluster Operator CRDs (`rabbitmq.com`) | Stage `05a-operators` uses `prune: false` |

A normal reinstall works. When the AIRM database, the `airm-rabbitmq-common-vhost-user` Secret, and the registration are all still present, stage `09-bootstrap` finds the existing registration and exits without changes.

### Reset to a clean state

These steps destroy data. Run them in order, and only on a cluster where no other workload depends on AIRM.

1. Suspend or delete the catalog HelmRelease and its stage Kustomizations first. Otherwise Flux recreates what you remove.
2. Delete the seed while AIRM is still running, so AIRM can release its finalizer. If the seed stays in `Terminating`, check for the `airm.silogen.ai/kaiwoqueueconfig-finalizer` finalizer before removing anything else.

   ```
   kubectl delete kaiwoqueueconfig kaiwo
   ```

3. Delete the `airm` and `keycloak` namespaces. This removes the AIRM database, RabbitMQ data, Keycloak realm, and the Secrets listed above.
4. In the release namespace, delete the stage Jobs (`airm-*`), the `airm-discovered` ConfigMap, and the `airm-gateway-tls` Secret.
5. Delete the Kaiwo and AIM Engine CRDs. This also deletes every `KaiwoJob`, `KaiwoService`, `KaiwoConfig`, `KaiwoQueueConfig`, and AIM resource. List the names first, then delete them:

   ```
   kubectl get crd | grep -E 'kaiwo\.silogen\.ai|aim\.eai\.amd\.com'
   ```

6. If you also want the RabbitMQ Cluster Operator reinstalled, delete the `rabbitmq-system` namespace and the `rabbitmq.com` CRDs. This deletes every `RabbitmqCluster`. Don't delete CloudNativePG or other NKP platform CRDs, since this application doesn't own them.
7. Reinstall the application.

Verify a clean state before reinstalling. The grep below should return nothing. `kubectl get kaiwoqueueconfig` should report that the server doesn't have that resource type.

```
kubectl get crd | grep -E 'kaiwo\.silogen\.ai|aim\.eai\.amd\.com'
kubectl get kaiwoqueueconfig
```

## Links

- [AMD Resource Manager documentation](https://enterprise-ai.docs.amd.com/en/v2.2.2/resource-manager/overview.html)
- [AMD Enterprise AI Suite 2.2.2 release notes](https://enterprise-ai.docs.amd.com/en/v2.2.2/release-notes.html)
