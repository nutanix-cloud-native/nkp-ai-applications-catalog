# Catalog manifest review rules

Apply these rules to files under `applications/`.

## Application structure

- A new or changed application version should follow the repository's documented layout: `metadata.yaml`, top-level `kustomization.yaml`, `helmrelease.yaml`, and the `helmrelease/` resources as applicable.
- Every resource file under `helmrelease/` must be listed by the corresponding `helmrelease/kustomization.yaml`.
- Every YAML document must end with `---` on its own line, including the final document.
- Use two-space indentation, lowercase kebab-case file names, and no underscores in file names.

## Metadata

- `metadata.yaml` must use `catalog.nkp.nutanix.com/v1/application-metadata`.
- Check required metadata fields: `displayName`, `description`, `category`, `licensing`, `scope`, `overview`, `supportLink`, `type`, `dependencies`, `requiredDependencies`, `icon`, and `allowMultipleInstances`.
- `requiredDependencies` must name hard prerequisites rather than hiding an incompatible feature.
- Check `nkpVersionSupport` whenever the application is only valid for a restricted NKP version range.
- Keep descriptions and overviews production-oriented and consistent with the actual manifests.

## Flux, namespaces, and substitutions

- Helm-based applications should use a dedicated application namespace, `targetNamespace: <app-namespace>`, and `install.createNamespace: true` where applicable.
- GitRepository/Kustomize-based applications must include `namespace.yaml` when they need the namespace created; `targetNamespace` alone does not create it.
- Use `${releaseName}`, `${releaseNamespace}`, `${workspaceNamespace}`, and related substitution variables instead of hardcoding deployment-specific names.
- Check that `OCIRepository`, `HelmRelease`, Flux `Kustomization`, and post-build substitution settings agree with one another.

## Dependencies and operational behavior

- Validate that declared hard and soft dependencies match the features actually enabled by the chart or manifests.
- Do not remove a dependency merely to work around a deployment failure; investigate whether the dependency is required by the enabled feature.
- Check readiness, timeout, retry, pruning, and RBAC behavior for changes that affect installation or upgrades.
- For dashboard or post-install integrations, verify namespace and variable substitutions end to end.
