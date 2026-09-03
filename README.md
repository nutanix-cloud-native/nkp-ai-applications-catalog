# NKP AI Applications Catalog

This repository serves as the catalog for AI applications available on the **Nutanix Kubernetes Platform (NKP)**. It contains the manifests, metadata, and Kustomize configurations required to deploy AI-focused applications through NKP using a GitOps workflow powered by Flux CD.

## Prerequisites

This project uses [Devbox](https://www.jetify.com/devbox) to provide a reproducible development environment with all required tools. Alternatively, install the tools manually.

### OCI Registry Authentication (Optional)

If you need to push Helm charts to `ghcr.io/nutanix-cloud-native/charts`, you have two options:

**Option 1: Use environment variables (recommended)**
```bash
export GITHUB_USERNAME=your-github-username
export GITHUB_TOKEN=ghp_your_github_token_here

# Then login works automatically
just login
```

**Option 2: Create a `.env.local` file**
```bash
# Copy the example file
cp .env.local.example .env.local

# Edit .env.local and add your credentials
# GHCR_USERNAME=your-github-username
# GHCR_PASSWORD=ghp_your_github_token_here

just login
```

To create a GitHub token:
1. Go to [GitHub Settings → Tokens](https://github.com/settings/tokens)
2. Generate a new token (classic) with `read:packages` and `write:packages` scopes
3. Copy the token to use as `GITHUB_TOKEN` or `GHCR_PASSWORD`

**Note:** For validation only, you can use `docker login ghcr.io` or `helm registry login ghcr.io` directly with your GitHub credentials instead of setting up environment variables.

### Quick Start with Devbox

```bash
# Install devbox (one-time)
curl -fsSL https://get.jetify.com/devbox | bash

# Enter the devbox shell (installs all tools automatically)
devbox shell

# Or, if you use direnv, just allow it and tools activate on cd
direnv allow
```

### Included Tools

| Tool | Purpose |
|------|---------|
| `just` | Task runner ([justfile](https://github.com/casey/just)) |
| `helm` | Helm chart pull/push |
| `git` | Version control |
| `gettext` | `envsubst` for variable substitution |
| `shfmt` | Shell script formatting |
| `shellcheck` | Shell script linting |
| `yq` | YAML querying/editing |
| `pre-commit` | Git hook framework |

> **Without Devbox:** install `just`, `helm`, `pre-commit`, `shfmt`, `shellcheck`, and `yq` manually. The `nkp` CLI is auto-downloaded by `just nkp-cli`.

## Repository Structure

```
.
├── README.md
├── devbox.json                # Devbox package list
├── devbox.lock                # Devbox lockfile
├── .envrc                     # direnv integration for devbox
├── .pre-commit-config.yaml    # Pre-commit hook configuration
├── .gitlint                   # Conventional commit message rules
├── .bloodhound.yml            # Kubernetes validation configuration
├── justfile                   # Task runner (install: https://github.com/casey/just)
├── just/                      # Modular just recipe files
│   ├── tools.just             # nkp CLI download + clean
│   ├── validate.just          # Catalog validation
│   └── release.just           # Bundle create, push, deploy, release pipeline
├── scripts/                   # Helper scripts
│   ├── login-oci-registry.sh  # Docker login to GHCR
│   ├── push-helm-to-oci.sh   # Mirror Helm chart from repo → OCI
│   └── check-app-versions.sh # Check if catalog apps have newer versions at source
└── applications/              # Application catalog entries
    └── <app-name>/
        └── <version>/
            ├── metadata.yaml          # Application metadata
            ├── .bloodhound.yaml       # Per-app validation overrides (optional)
            ├── kustomization.yaml     # Top-level Kustomize config
            ├── helmrelease.yaml       # Flux Kustomization resource
            └── helmrelease/
                ├── kustomization.yaml # Kustomize config for manifests
                ├── cm.yaml            # ConfigMap for default values (optional)
                └── helmrelease.yaml   # OCIRepository + HelmRelease resources
```

### Key Files

| File | Description |
|------|-------------|
| `metadata.yaml` | Defines application display name, description, categories, licensing, scope, and other metadata following the `catalog.nkp.nutanix.com/v1/application-metadata` schema. |
| `kustomization.yaml` | Kustomize configuration that references the Flux resources for the application. |
| `helmrelease.yaml` | Flux `Kustomization` resource that points to the `helmrelease/` subdirectory. |
| `.bloodhound.yaml` | Optional per-version validation config (e.g., `strict: false`, `skip_types` for CRDs). |
| `helmrelease/` | Contains the actual Kubernetes manifests including OCIRepository, HelmRelease, and ConfigMap resources. |

## Adding a New Application

### Step 1: Generate the Application Scaffold

Use the `nkp` CLI to generate the catalog entry for your application. Provide the application name and version:

```bash
nkp generate catalog-repository --apps=<app-name>=<version>
```

**Example:**

```bash
nkp generate catalog-repository --apps=kagent=0.7.13
```

This will create the directory structure and required files under `applications/<app-name>/<version>/`.

### Step 2: Customize the Generated Files

After generation, review and update the following as needed:

- **`metadata.yaml`** -- Fill in the application metadata:
  - `displayName` -- Human-readable name
  - `description` -- Short description of the application
  - `category` -- Array of categories (e.g., `artificial-intelligence`, `networking`, `ai-ml`)
  - `licensing` -- Supported license tiers (e.g., `["Pro", "Ultimate"]`)
  - `scope` -- Deployment scope (e.g., `["workspace", "project"]`)
  - `overview` -- Detailed markdown overview of the application
  - `supportLink` -- Link to documentation or support

- **`helmrelease/helmrelease.yaml`** -- Configure the OCI chart reference:
  - Set the `url` to the OCI registry containing the Helm chart
  - Set the `tag` to the chart version
  - Define any default values in a ConfigMap (`cm.yaml`)

- **`.bloodhound.yaml`** (optional) -- Add per-version validation overrides:
  - Set `strict: false` if the chart emits resources with extra fields
  - Add custom resource types to `skip_types` (e.g., `kagent.dev/v1alpha2/Agent`)

### Step 3: Validate the Catalog Repository

Run the validation command to ensure all manifests are correctly structured and valid:

```bash
just validate
# or: nkp validate catalog-repository --repo-dir=.
```

This validates:
- Kubernetes manifest correctness
- Required file structure
- Kustomize configuration integrity
- Metadata schema compliance

Fix any reported errors before committing your changes.

### Step 4: Create the Catalog Bundle

Package the catalog into a distributable bundle:

```bash
just create-bundle v0.1.0
# or: nkp create catalog-bundle --collection-tag v0.1.0
```

This creates an OCI-compatible bundle (e.g., `nkp-ai-applications-catalog.tar`) containing all applications and metadata.

### Step 5: Push the Bundle to a Registry

Push the bundle to an OCI registry so it can be consumed by NKP clusters:

```bash
just push-bundle
# or: nkp push bundle --bundle ./nkp-ai-applications-catalog.tar --to-registry <registry>
```

> **Tip:** Steps 3-5 can be combined into a single command: `just release v0.1.0`

### Airgapped Bundle Build and Push (Generic)

Use this flow when preparing a disconnected/offline bundle that includes images
and OCI artifacts. The airgapped recipes render `.release/full.yaml.tmpl`
(`includeApplicationImages: true`), so the tarball bundles the container images
and OCI artifacts needed on a disconnected cluster — not just the manifests.

```bash
# Optional: if Docker is not on default socket (Rancher Desktop / Colima)
export DOCKER_HOST=unix://$HOME/.rd/docker.sock

# 1) Validate manifests
just validate

# 2) Build a single-app airgapped bundle → <app>-<version>-full.tar
just create-application-airgapped-bundle <app> <version>

# 3) Push the airgapped bundle to the target registry
nkp push bundle --bundle ./<app>-<version>-full.tar --to-registry <registry>
```

Example:

```bash
just create-application-airgapped-bundle kai-scheduler 0.15.2
nkp push bundle --bundle ./kai-scheduler-0.15.2-full.tar --to-registry oci://ghcr.io/<org-or-user>
```

To build a whole collection instead of a single app, use the collection recipe
with a `tagName` from `.release/dev.yaml` (e.g. `2.19-dev`). It writes
`nkp-ai-applications-catalog-<tag>-full.tar`:

```bash
just create-collection-airgapped-bundle 2.19-dev
nkp push bundle --bundle ./nkp-ai-applications-catalog-2.19-dev-full.tar --to-registry oci://ghcr.io/<org-or-user>
```

### Step 6: Commit and Push

Once validation passes, commit your changes and open a pull request:

```bash
git add applications/<app-name>/
git commit -m "Add <app-name> <version> to AI applications catalog"
git push origin <your-branch>
```

## Using the Catalog on a Cluster

To deploy the catalog collection on an NKP cluster:

```bash
just add-to-cluster <workspace-name> v0.1.0

# or directly:
nkp create catalog-collection \
  --url oci://ghcr.io/nutanix-cloud-native/nkp-ai-applications-catalog/collection \
  --tag v0.1.0 \
  --workspace <workspace-name>
```

This makes all applications in the catalog available for deployment in the specified workspace.

## Handling Helm Repository Charts (non-OCI)

If the application Helm chart is hosted in a traditional Helm repository (not OCI), you need to pull it locally and push it to an OCI-compliant registry before adding it to the catalog. Any OCI artifact-compliant registry works, including **ghcr.io**, **Harbor**, **Docker Hub**, **Amazon ECR**, **Azure ACR**, **Google Artifact Registry**, etc.

> **Note:** This may be required for licensing or distribution reasons (TBD).

The `mirror-chart-from-repo` recipe automates pulling the chart and pushing it to OCI:

```bash
# From a Helm repository (recommended)
just mirror-chart-from-repo <repo-url> <chart> <version> [oci-registry]

# From an upstream OCI registry
just mirror-chart-from-oci <oci-url> <version> [oci-registry]

# Or directly via script
./scripts/push-helm-to-oci.sh <repo-url> <chart> <version> <oci-registry>
```

**Examples:**

```bash
# Ollama (from Helm repo)
just push-ollama 1.39.0

# vLLM (from Helm repo)
just push-vllm 0.1.1

# Any chart from a Helm repo
just mirror-chart-from-repo https://charts.example.com myapp 1.0.0 oci://ghcr.io/my-org/myapp

# Any chart from an upstream OCI registry
just mirror-chart-from-oci oci://ghcr.io/envoyproxy/gateway-helm v1.5.0
```

This will:
1. Add the Helm repo and pull the chart
2. Push the `.tgz` to the OCI registry

Then in the application's `helmrelease/helmrelease.yaml`, reference the OCI registry URL:

```yaml
spec:
  ref:
    tag: <version>
  url: oci://<registry>/<your-org>/<chart-name>
```

## Baking Kustomize-only Apps into Charts

Some apps (e.g. Kubeflow components) have **no usable upstream Helm chart** and
ship as Kustomize trees with remote/`../` bases that Flux can't resolve in
air-gapped installs. The `bake` tool (`tools/bake`) renders each app's pinned
upstream overlays into one self-contained, air-gappable manifest **and** a small
parameterized Helm chart, giving the baked app a `configOverrides` surface.

```bash
just bake <app> [version]   # render + bake from scripts/bake-apps.yaml
just bake-check             # re-bake all; fail if committed artifacts drifted (CI gate)
```

See [`tools/bake/README.md`](tools/bake/README.md) for how baking works, when to
use it, the config schema, and full usage. If an app already publishes a clean
Helm chart, add it the normal way instead (see [Adding a New Application](#adding-a-new-application)).

### Manual CI publish for baked charts

Use the GitHub Actions workflow `Publish Baked Charts to GHCR` when you want CI
credentials to bake and publish baked charts (for example `kubeflow-pipelines`)
to `oci://ghcr.io/nutanix-cloud-native/charts`.

- Trigger it manually from GitHub Actions (`workflow_dispatch` only).
- Leave `baked_chart_apps` empty to publish only baked charts changed under `charts/<app>/`
  between `compare_base_ref` and `compare_head_ref`.
- Set `baked_chart_apps` (for example `kubeflow-pipelines`) to force a publish even when
  diff-based detection is not what you want.
- The workflow runs `just bake <app>` before `just push-baked-chart <app>` and
  fails on bake drift checks.
- The workflow only pushes packages; if visibility is not public, update package
  visibility in GHCR package settings manually.

### Manual CI publish for first-party charts

Use `Publish First-Party Charts to GHCR` for hand-authored charts such as
`kubeflow-platform` (no bake step).

- Trigger it manually and set `chart` (default `kubeflow-platform`).
- The workflow runs `helm lint`, then `helm package` / `helm push`.
- Local equivalent: `just login && helm package charts/kubeflow-platform && helm push kubeflow-platform-*.tgz oci://ghcr.io/nutanix-cloud-native/charts`.

## Sample Apps (Demo)

| Application | Version | Description |
|-------------|---------|-------------|
| **demo-full-rag** | 1.1.0 | Complete RAG app using Weaviate (vector DB) and Ollama (embeddings + LLM). Depends on Weaviate and Ollama. |

These apps demonstrate catalog composability and dependency flow. See [docs/demo-script.md](docs/demo-script.md) for the full demo walkthrough.

**Kubeflow:** All Kubeflow components use [kubeflow/manifests v1.11.0](https://github.com/kubeflow/manifests/releases/tag/v1.11.0). See [docs/KUBEFLOW-V1.11-MIGRATION.md](docs/KUBEFLOW-V1.11-MIGRATION.md) for migration notes and required fixes.

## Existing Applications

| Application | Version | Chart | Description |
|-------------|---------|-------|-------------|
| agentgateway | 2.2.0 | `oci://cr.agentgateway.dev/charts/agentgateway` | AI-focused gateway for security, observability, and traffic management of LLM workloads |
| vllm | 0.1.1 | `oci://ghcr.io/nutanix-cloud-native/charts/vllm` | High-throughput inference and serving engine for large language models |
| flowise | 6.0.0 | `oci://ghcr.io/nutanix-cloud-native/charts/flowise` | Drag-and-drop UI to build customized LLM flows with LangChain |

## Scripts & Justfile

All helper scripts live in `scripts/` and are orchestrated via a [`justfile`](https://github.com/casey/just). Run `just` to see all available recipes.

### Quick Reference

| Recipe | Description |
|--------|-------------|
| `just check` | Quick check: run pre-commit hooks only |
| `just check-all` | Full check: pre-commit + catalog validation (ready to push) |
| `just check-versions [--json] [--app NAME]` | Check if catalog apps have newer versions at source (requires helm, crane for OCI) |
| `just pre-commit` | Run pre-commit hooks and gitlint |
| `just validate` | Validate catalog manifests (auto-downloads `nkp` CLI) |
| `just login` | Docker login to GHCR (reads `.env.local`) |
| `just mirror-chart-from-repo <url> <chart> <ver> [oci]` | Mirror a Helm repo chart to OCI |
| `just mirror-chart-from-oci <oci-url> <ver> [oci]` | Mirror a chart from upstream OCI to our OCI |
| `just push-ollama [version]` | Shortcut for ollama (default: `1.39.0`) |
| `just push-vllm [version]` | Shortcut for vllm (default: `0.1.1`) |
| `just push-openwebui [version]` | Shortcut for open-webui (default: `12.0.1`) |
| `just push-weaviate [version]` | Shortcut for weaviate (default: `17.7.0`) |
| `just push-coder [version]` | Shortcut for coder (default: `2.30.2`) |
| `just push-mlflow [version]` | Shortcut for mlflow (default: `1.8.1`) |
| `just push-flowise [version]` | Shortcut for flowise (default: `6.0.0`) |
| `just push-jupyterhub [version]` | Shortcut for jupyterhub (default: `4.3.2`) |
| `just push-milvus-operator [version]` | Shortcut for milvus-operator (default: `1.3.6`) |
| `just add-<app>` | Push chart + generate scaffold (e.g. `add-ollama`, `add-weaviate`) — see dev-commands.md |
| `just bake <app> [version]` | Render a Kustomize-only app into an air-gappable manifest + chart (see [tools/bake](tools/bake/README.md)) |
| `just bake-check` | Re-bake all apps; fail if committed artifacts drifted |
| `just push-baked-chart <app>` | Package and push `kubeflow-pipelines` or `kubeflow-central-dashboard` |
| `Publish Baked Charts to GHCR` (GitHub Actions) | Manual CI workflow to bake and push changed baked charts to GHCR using CI credentials |
| `Publish First-Party Charts to GHCR` (GitHub Actions) | Manual CI workflow to lint and push hand-authored charts (for example `kubeflow-platform`) |
| `just create-bundle [tag]` | Create catalog bundle (default: `v0.1.0`) |
| `just push-bundle [registry]` | Push bundle to OCI registry |
| `just add-to-cluster [workspace] [tag]` | Deploy catalog to NKP cluster |
| `just release [tag] [registry]` | Full pipeline: validate, bundle, push |
| `just nkp-cli` | Download `nkp` CLI to `.local/bin/` |
| `just clean` | Remove downloaded tools (`.local/`) |

### Scripts

| Script | Description |
|--------|-------------|
| `scripts/login-oci-registry.sh` | Login to GHCR; also sourceable to export `GHCR_USERNAME`/`GHCR_PASSWORD` |
| `scripts/push-helm-to-oci.sh` | Mirror a Helm chart from repo to OCI (used by `mirror-chart-from-repo`) |
| `scripts/check-app-versions.sh` | Check if catalog apps have newer versions at Helm repo or OCI source |
| `scripts/demo-catalog.sh` | Build demo apps, create bundle, deploy (see `docs/demo-script.md`) |

### Typical Workflow

```bash
# 0. Enter dev environment (all tools available)
devbox shell

# 1. Login to OCI registry
just login

# 2. Push a Helm chart to OCI (e.g. ollama 1.39.0)
just push-ollama

# 3. Run all checks before committing (pre-commit + validation)
just check-all

# 4. Validate, bundle, and push the catalog
just release v0.1.0

# 5. Deploy to a cluster
just add-to-cluster dm-dev-workspace v0.1.0
```

## Common Patterns

All applications in this catalog follow these conventions:

- **Flux CD** is used for GitOps-based deployment and reconciliation.
- **Kustomize** organizes and overlays Kubernetes resources.
- **Variable substitution** uses NKP-injected variables such as `${releaseName}`, `${releaseNamespace}`, `${clusterName}`, `${clusterUUID}`, and `${clusterType}` for dynamic configuration.
- **HelmRelease + OCIRepository** is the standard pattern for deploying charts via Flux.

## Validation

The repository uses `.bloodhound.yml` for Kubernetes manifest validation with strict mode enabled against Kubernetes v1.34.0. Substitution variables (`releaseNamespace`, `workspaceNamespace`) are configured to allow Flux variable references to pass validation.

Individual applications can override validation settings with a `.bloodhound.yaml` file in their version directory (e.g., to set `strict: false` or add `skip_types` for custom CRDs).
