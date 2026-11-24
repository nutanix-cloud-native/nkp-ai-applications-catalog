# NKP AI Applications Catalog — general review rules

Review changes as declarative GitOps catalog changes, not as application source-code changes.

## Correctness and safety

- Verify that every referenced file, resource, chart, OCI source, and Kustomize entry exists and is wired into the relevant `kustomization.yaml`.
- Check that changes preserve Flux reconciliation behavior and do not silently disable readiness, pruning, retries, or dependency ordering.
- Check that generated artifacts are not edited when the repository instructions identify an authored source or generator as the source of truth.
- Treat changes to image references, chart references, versions, registries, RBAC, namespaces, CRDs, and post-install Jobs as high-risk.
- Flag hardcoded release-specific values where the repository's substitution variables should be used.
- Check that changes do not expose credentials, tokens, private endpoints, or other secrets.

## Validation expectations

- Confirm that the change is covered by the repository's validation workflow where applicable.
- For application changes, expect catalog validation and relevant pre-commit checks to be run.
- For release or bundle changes, check that the change explains how the resulting bundle or collection was validated.
- Do not treat an AI review result as a substitute for CI, catalog validation, deployment testing, or human approval.

## Review style

- Prioritize correctness, deployability, upgrade behavior, and user-visible catalog behavior over cosmetic YAML preferences.
- Report only actionable findings supported by the changed files and repository context.
- Do not comment merely because a pattern differs from an existing application unless the difference creates a concrete risk.
