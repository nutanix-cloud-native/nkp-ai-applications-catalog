# AGENTS.md

Guidelines for AI agents working on the NKP AI Applications Catalog.

## Project Overview

This is a GitOps catalog repository for AI applications on the Nutanix Kubernetes Platform (NKP). It contains Kubernetes manifests, metadata, and Kustomize configurations for deploying AI applications via Flux CD. There is no application source code here — only declarative YAML manifests.

## Repository Structure

```
applications/
  <app-name>/
    .catalog-source.yaml              # (optional) Helm repo source info for tooling
    <version>/
      .bloodhound.yaml                # (optional) per-app validation overrides
      metadata.yaml                   # Application metadata (display name, description, etc.)
      kustomization.yaml              # Top-level Kustomize config — references helmrelease.yaml
      helmrelease.yaml                # Flux Kustomization resource pointing to ./helmrelease/
      helmrelease/
        kustomization.yaml            # Kustomize config listing resources in this directory
        helmrelease.yaml              # OCIRepository + HelmRelease (or Job-based install)
        cm.yaml                       # ConfigMap for default Helm values
        namespace.yaml                # (optional) Namespace definition
        <app>-install.yaml            # (optional) Installation Job with RBAC
        *-cm.yaml                     # (optional) Additional ConfigMaps (e.g. UI dashboard)
```

## Adding a New Application

When asked to add a new application, follow this exact workflow. Use an existing application (e.g. `agentgateway/2.2.0`, `kagent/0.7.13`, or `vllm/0.1.1`) as a reference.

### NKP CLI Workflow

```bash
# 1. Generate the application scaffold
nkp generate catalog-repository --apps=<app-name>=<version>

# 2. Customize the generated files (metadata.yaml, helmrelease, .bloodhound.yaml, etc.)

# 3. Validate the catalog repository
nkp validate catalog-repository --repo-dir=.

# 4. Create the catalog bundle
nkp create catalog-bundle --collection-tag v0.1.0

# 5. Push the bundle to an OCI registry
nkp push bundle --bundle ./nkp-ai-app-catalog.tar --to-registry <registry>
```

### Deploying the Catalog on a Cluster

```bash
nkp create catalog-collection \
  --url oci://ghcr.io/nutanix-cloud-native/nkp-ai-applications-catalog/nkp-ai-applications-catalog/collection \
  --tag v0.1.0 \
  --workspace <workspace-name>
```

### Handling Helm Repository Charts (non-OCI)

If the Helm chart is in a traditional Helm repository (not OCI), pull it locally and push to your own OCI registry:

```bash
helm repo add <repo-name> <repo-url>
helm search repo <repo-name>/<chart> --versions
helm pull <repo-name>/<chart>
helm push <chart>-<version>.tgz oci://<your-oci-registry>/<chart>
```

Then reference the OCI registry URL in `helmrelease/helmrelease.yaml`.

### Required files

1. **`applications/<app>/<version>/metadata.yaml`** — must use schema `catalog.nkp.nutanix.com/v1/application-metadata` with fields: `displayName`, `description`, `category`, `licensing`, `scope`, `overview`, `supportLink`, `type`, `dependencies`, `icon`, `allowMultipleInstances`.

2. **`applications/<app>/<version>/kustomization.yaml`** — always:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
   - helmrelease.yaml
   ---
   ```

3. **`applications/<app>/<version>/helmrelease.yaml`** — Flux `Kustomization` resource:
   ```yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: ${releaseName}-helmrelease
     namespace: ${releaseNamespace}
   spec:
     interval: 6h0m0s
     path: ./helmrelease
  postBuild:
    substitute:
      releaseName: ${releaseName}
      releaseNamespace: ${releaseNamespace}
      workspaceNamespace: ${workspaceNamespace}  # required if using UI dashboard ConfigMaps or post-install Jobs in workspace ns
    prune: true
     retryInterval: 1m0s
     sourceRef:
       kind: OCIRepository
       name: ${releaseName}-source
       namespace: ${releaseNamespace}
     timeout: 1m0s
     wait: true
   ---
   ```

4. **`applications/<app>/<version>/helmrelease/kustomization.yaml`** — lists all resources in the directory.

5. **`applications/<app>/<version>/helmrelease/helmrelease.yaml`** — contains an `OCIRepository` (chart source) and a `HelmRelease` (or Job-based install manifest). Uses `${releaseName}` and `${releaseNamespace}` substitution variables.

6. **`applications/<app>/<version>/helmrelease/cm.yaml`** — ConfigMap for default Helm values:
   ```yaml
   apiVersion: v1
   data:
     values.yaml: ""
   kind: ConfigMap
   metadata:
     name: ${releaseName}-${appVersion}-defaults
     namespace: ${releaseNamespace}
   ---
   ```

### Optional files

- `namespace.yaml` — only needed for Job-based installs that create their own namespace.
- `<app>-install.yaml` — Job + ServiceAccount + ClusterRole + ClusterRoleBinding for apps that need a custom installer instead of a plain HelmRelease.
- `*-cm.yaml` — extra ConfigMaps (e.g. UI dashboard integration).
- `.bloodhound.yaml` — per-app validation overrides (e.g. `strict: false`).
- `.catalog-source.yaml` — Helm repo metadata for version-check tooling.

## YAML Conventions

- **Every YAML document ends with `---`** on its own line (including the last document in a file).
- **Multi-document files** separate resources with `---`.
- Use **2-space indentation** consistently.
- Strings containing special characters or multi-line content use the `|` block scalar style.
- File names are lowercase with hyphens. No underscores.

## Variable Substitution

Flux performs post-build variable substitution. Always use these variables instead of hardcoded values:

| Variable | Purpose |
|----------|---------|
| `${releaseName}` | The release/instance name set by NKP at deploy time |
| `${releaseNamespace}` | The target namespace set by NKP at deploy time |
| `${workspaceNamespace}` | The NKP workspace namespace (used in UI dashboard ConfigMaps) |

Never hardcode namespace or release name in places where these variables should be used.

## metadata.yaml Schema

Required fields:

| Field | Type | Description |
|-------|------|-------------|
| `schema` | string | Always `catalog.nkp.nutanix.com/v1/application-metadata` |
| `displayName` | string | Human-readable application name |
| `description` | string | Short description (1-3 sentences) |
| `category` | list | e.g. `["artificial-intelligence"]`, `["ai-ml", "networking"]` |
| `licensing` | list | Supported tiers: `["Pro", "Ultimate"]` |
| `scope` | list | Deployment scope: `["workspace"]`, `["project"]`, or both |
| `type` | string | Usually `custom` |
| `overview` | string | Markdown overview; use **Overview**, **Key capabilities**, **Dependencies** (if any), **Prerequisites** (if any), and **Resources** (docs/project/chart links). Keep concise and production-oriented. |
| `supportLink` | string | URL to documentation or support |
| `dependencies` | list | List of dependency app names (empty `[]` if none) |
| `icon` | string | URL to an SVG/PNG icon (empty `""` if none) |
| `allowMultipleInstances` | bool | Whether multiple instances can be deployed |
| `nkpVersionSupport` | string | NKP version constraint, e.g. `">=2.17.0"` for 2.17 and above (optional) |

## Validation

- The root `.bloodhound.yml` configures Kubernetes schema validation (strict mode, k8s v1.34.0).
- Per-app overrides go in `applications/<app>/<version>/.bloodhound.yaml` (e.g. `strict: false` for charts that emit non-standard fields).
- Validate with: `nkp validate catalog-repository --repo-dir=.`
- Create bundle with: `nkp create catalog-bundle --collection-tag v0.1.0`
- Push bundle with: `nkp push bundle --bundle ./nkp-ai-app-catalog.tar --to-registry <registry>`
- Deploy on cluster with: `nkp create catalog-collection --url oci://ghcr.io/nutanix-cloud-native/nkp-ai-applications-catalog/nkp-ai-applications-catalog/collection --tag v0.1.0 --workspace <workspace-name>`
- Substitution variables `releaseNamespace` and `workspaceNamespace` default to `kommander` and `workspace` respectively during validation.

## Common Pitfalls

- Forgetting the trailing `---` at the end of YAML documents.
- Hardcoding namespaces or release names instead of using `${releaseName}` / `${releaseNamespace}`.
- Not listing a new resource file in the corresponding `kustomization.yaml`.
- Using `strict: true` validation for Helm charts that emit extra/unknown fields — override with a per-app `.bloodhound.yaml`.
- Missing required fields in `metadata.yaml`.

## Commit Messages

Follow the pattern: `Add <app-name> <version> to AI applications catalog` for new applications, or `Update <app-name> <version> ...` for modifications.
