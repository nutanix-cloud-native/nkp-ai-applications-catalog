# AMD Resource Manager 2.0.1

This document contains operational and implementation details for maintainers
and users of the NKP catalog package. Catalog-facing information is maintained
in `metadata.yaml`.

Catalog version `2.0.1` installs AIRM `2.0.0`. It replaces the local
orchestration chart used by catalog `2.0.0` with static Flux Kustomizations,
in the same style as the Harbor catalog entry. The stage scripts are unchanged
from `2.0.0`; only the way stages are defined and configured differs.

## Versioning and Upgrades

Only one version of this application can be installed in a cluster
(`allowMultipleInstances: false`). Upgrades keep the same release name, so the
stage Kustomizations keep the same names (`${releaseName}-<stage>`) and update
in place. Each catalog version directory is self-contained: it holds its own
stage definitions, scripts, and version pins, with no separately published
chart to keep in sync.

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

The catalog entry's `helmrelease.yaml` is a Flux Kustomization that applies
`./helmrelease`. That directory contains `cm.yaml` and one Flux Kustomization
per stage under `helmrelease/kustomizations/`. There is no local chart and no
`HelmRelease` for the application itself.

Each stage then deploys its own sources. The following AIRM 2.0.0 charts are
pulled from OCI registries by the stages that use them:

- `amdenterpriseai/airm-api-chart`
- `amdenterpriseai/airm-agent-chart`
- `amdenterpriseai/airm-cnpg-chart`
- `amdenterpriseai/airm-rabbitmq-chart`

Chart locations, image versions, tool images, and supporting component versions
are maintained in `helmrelease/cm.yaml`. To override a value, create the
optional ConfigMap `airm-config-overrides` in the catalog release namespace
with the same flat key/value layout; its keys take precedence over `cm.yaml`.

Stage tuning is only read from `airm-config-overrides` (defaults are built into
the stage Kustomizations): `stagesInterval` (1m), `stagesRetryInterval` (1m),
`stagesTimeout` (5m, stages 01-04), `stagesPrune` (true), `stagesWait` (true),
and per-stage timeouts `stagePreflightTimeout` (25m), `stageOperatorsTimeout`,
`stageInfrastructureTimeout`, `stageRabbitmqConfigTimeout`,
`stageAgentCrdsTimeout`, `stageManagementTimeout`, `stageIdentitySyncTimeout`,
`stagePostInstallTimeout` (12m each), `stageBootstrapTimeout` (15m),
`stageGatewayTlsTimeout` (20m) and `stageAgentTimeout` (10m). They are applied
by the parent Kustomization, which reconciles every 5m, so changes take up to
5m to reach the stages.

## Staged Reconciliation

Each stage is a Flux Kustomization in `helmrelease/kustomizations/` with
explicit dependencies and health checks, so a failed prerequisite prevents
later stages from running. `00-namespace` creates the `airm` namespace with
`prune: false`, so reconciling or removing the app never deletes it.

The current stage sequence is:

1. `00-preflight` discovers the domain, StorageClass, and Prometheus endpoint,
   and verifies required platform services.
2. `01-secrets` generates and validates the Kubernetes Secrets needed by AIRM,
   PostgreSQL, RabbitMQ, and Keycloak.
3. `02-gateway` validates Gateway API support and creates the AIRM Gateway.
4. `03-keycloak` installs and configures Keycloak.
5. `04-storage` validates and prepares the selected StorageClass.
6. `05-operators` verifies the required database operator and installs or
   verifies the RabbitMQ Cluster Operator.
7. `05-infrastructure` deploys PostgreSQL and RabbitMQ.
8. `06-rabbitmq-config` configures the RabbitMQ resources used by AIRM.
9. `07-agent-crds` installs the required Kaiwo and AIM Engine CRDs.
10. `08-management` deploys the AIRM API and UI.
11. `09-bootstrap` registers the local cluster with AIRM.
12. `10-identity-sync` reconciles the registered cluster's RabbitMQ identity.
13. `11-gateway-tls` creates the self-signed Gateway certificate and routes.
14. `12-agent` deploys the local AIRM agent.
15. `13-post-install` verifies the completed installation and emits an access
    summary.

The parent Kustomization (`${releaseName}-helmrelease`) reconciles every six
hours with `prune: true`. If a stage Kustomization is manually deleted or
modified, it is restored on that reconcile.

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

Stage `07-agent-crds` downloads pinned Kaiwo and AIM Engine release artifacts.
It verifies each artifact with its catalog-pinned SHA-256 digest before applying
anything to the cluster.

For Kaiwo, the stage extracts and installs only the CRDs from the verified
release manifest. For AIM Engine, it applies the verified CRD release file. The
stage then waits for the required CRDs to become established and creates the
cluster-scoped `KaiwoQueueConfig/kaiwo` seed object required for AIRM quota
operations.

The RabbitMQ Cluster Operator release manifest is also versioned and protected
by a pinned SHA-256 digest. Versions and digests are defined in
`helmrelease/cm.yaml` and must be updated together when upgrading these
artifacts.

Digest verification protects downloaded release content from changing
unexpectedly at a pinned URL. It does not replace review and validation of a
new artifact before its digest is accepted into the catalog.

### Kaiwo and AIM API coverage

The current release uses the Kaiwo CRDs to provide the Kubernetes API types
expected by the AIRM agent. It also creates the cluster-scoped
`KaiwoQueueConfig/kaiwo` object that AIRM uses to record project quota and
resource-allocation state. Quota changes can be inspected with:

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
2. Update the corresponding SHA-256 digest where verification is supported.
3. Render and inspect the orchestration chart.
4. Validate the catalog repository.
5. Build a fresh catalog bundle and publish it under a new immutable tag.
6. Reconcile the NKP catalog collection and verify every stage becomes Ready.

## Links

- [AMD Resource Manager documentation](https://enterprise-ai.docs.amd.com/en/v2.2.2/resource-manager/overview.html)
- [AMD Enterprise AI Suite 2.2.2 release notes](https://enterprise-ai.docs.amd.com/en/v2.2.2/release-notes.html)
