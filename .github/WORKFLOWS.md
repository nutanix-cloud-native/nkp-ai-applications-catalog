# GitHub Actions workflows — what runs when

This repo uses the same CI pattern as [nkp-nutanix-product-catalog](https://github.com/nutanix-cloud-native/nkp-nutanix-product-catalog) and [nkp-partner-catalog](https://github.com/nutanix-cloud-native/nkp-partner-catalog): checks on every PR/push, manifest validation when catalog content changes, and a manual workflow to publish the catalog bundle to OCI.

---

## 1. On every push to `main` and on every pull request

**Workflow: [checks.yaml](workflows/checks.yaml)**

Runs in parallel:

| Job         | Runner                      | What it does |
|------------|-----------------------------|--------------|
| **lint-gha** | self-hosted-nutanix-docker-medium | Checks all workflow YAML with [actionlint](https://github.com/rhysd/actionlint); reports to PR review via reviewdog. |
| **pre-commit** | self-hosted-nutanix-medium | Nix + devbox → runs `just pre-commit` (trailing whitespace, YAML, line endings, gitlint, shellcheck, etc.). Skips `no-commit-to-branch` and `actionlint-system` so CI doesn’t duplicate the actionlint job. |

**Sequence:** Both jobs start at the same time. The PR (or push) is considered passing only when both succeed.

---

## 2. On PR and on push to `main` / `v*` (only when catalog changed)

**Workflow: [manifest.yml](workflows/manifest.yml)**

Runs only if there are changes under `applications/**` (`if: hashFiles('applications/**') != ''`).

On PRs, the workflow is gated by [action-check-approvals](https://github.com/nutanix-cloud-native/action-check-approvals): validation runs only after the PR has one of `integration-test` or `skip_integration` and the required number of approvals (default: 1).

| Step | What it does |
|------|-------------------------------|
| Check integration test allowance status | On PRs only: gates until approvals + labels are met. |
| Checkout | Current commit. |
| Install Nix | Needed for devbox. |
| Install devbox | Uses `devbox.json` / `devbox.lock`. |
| Run catalog validation | `devbox run -- just validate` → runs `nkp validate catalog-repository` on the repo. |

**Sequence:** Single job. If `applications/**` is unchanged, the job is skipped. Otherwise it validates the catalog (metadata, kustomizations, helmrelease, bloodhound, etc.).

---

## 3. Manual publish (workflow_dispatch)

**Workflow: [publish-oci-artifacts.yaml](workflows/publish-oci-artifacts.yaml)**

Triggered from the Actions tab with inputs:

- **COLLECTION_TAG** (required): e.g. `v0.1.0`
- **REGISTRY** (optional): OCI base URL; default `oci://ghcr.io/nutanix-cloud-native/nkp-ai-applications-catalog`

| Step | What it does |
|------|-------------------------------|
| Checkout | Current ref (usually `main`). |
| Install Nix + devbox | Same as manifest workflow. |
| Login to GHCR | So the bundle can be pushed. |
| Create and publish | `just publish-artifacts <REGISTRY> <COLLECTION_TAG>` → `create-bundle` then `push-bundle` (builds the catalog tarball and pushes it to the OCI registry). |

**Sequence:** One job. You choose the tag and optionally the registry; the workflow builds the bundle and publishes it.

---

## 4. Manual publish chart to OCI (workflow_dispatch)

**Workflow: [publish-chart-oci.yaml](workflows/publish-chart-oci.yaml)**

Triggered from the Actions tab to publish a Helm chart from a Helm repo to an OCI registry (e.g. GHCR). Inputs:

- **chart_repo** (required): Source repository URL for the chart (e.g., https://mesosphere.github.io/charts/staging)
- **chart_name** (required): Helm chart name (e.g., ndk, nutanix-ai, kserve, envoy-gateway etc.)
- **chart_version** (required): Helm chart version
- **target_oci_registry** (optional): Target OCI registry; default `oci://ghcr.io/nutanix-cloud-native/nkp-ai-charts`

| Step | What it does |
|------|-------------------------------|
| Checkout | Current ref. |
| Install Helm | Installs Helm 3. |
| Login to GHCR | So the chart can be pushed. |
| Pull chart | Adds repo, updates, pulls the specified chart/version. |
| Push chart | Pushes the chart tarball to the target OCI registry. |

---

## Summary

| Trigger | Workflows that run |
|--------|---------------------|
| Push to `main` | **checks** (lint-gha + pre-commit), **manifest** (only if `applications/**` changed). |
| Open / update / reopen PR | **checks** (lint-gha + pre-commit), **manifest** (only if `applications/**` changed). |
| Merge group (e.g. merge queue) | **checks** (lint-gha + pre-commit). |
| Manual “Publish OCI Artifacts” | **publish-oci-artifacts** only. |
| Manual "Publish Chart to GHCR" | **publish-chart-oci** only. |

All workflows use **self-hosted Nutanix runners** as defined in [actionlint.yaml](actionlint.yaml).
