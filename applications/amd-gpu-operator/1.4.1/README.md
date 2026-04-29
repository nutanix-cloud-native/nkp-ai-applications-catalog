# AMD GPU Operator

NKP catalog component for the [AMD GPU Operator](https://github.com/ROCm/gpu-operator).

## Dependencies

This component requires `amd-kmm-operator` to be installed first. The dependency is enforced via both `metadata.yaml` (`requiredDependencies`) and Flux `HelmRelease.spec.dependsOn`.

## Default Configuration

The following subcharts are **disabled** by default because they are provided by other NKP components:

| Subchart | Disabled | Provided By |
|---|---|---|
| `kmm` | `kmm.enabled: false` | `amd-kmm-operator` |
| `node-feature-discovery` | `node-feature-discovery.enabled: false` | Kommander |

## Private Registry Setup

When using a private registry for built driver images, the default `DeviceConfig` CR must have `spec.driver.image` and `spec.driver.imageRegistrySecret` set:

```yaml
deviceConfig:
  spec:
    driver:
      image: "registry.example.com:5000/drivers/amdgpu_kmod"
      imageRegistrySecret:
        name: "kmm-registry-dockerconfig"
```

These values are set in `helmrelease/cm.yaml`. Update `spec.driver.image` to match your registry path before deploying.

## ServiceAccount Reconciler

A CronJob (`amd-gpu-operator-sa-reconciler`) runs every 5 minutes and ensures the `kmm-registry-dockerconfig` imagePullSecret is present on the `amd-gpu-operator-kmm-module-loader` ServiceAccount. This is additive — existing imagePullSecrets are preserved.
