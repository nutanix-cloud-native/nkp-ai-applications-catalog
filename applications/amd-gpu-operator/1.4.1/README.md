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

## NFD Toleration Requirement

Kommander's NFD worker DaemonSet must include the following toleration to discover AMD GPUs on tainted nodes:

```yaml
tolerations:
  - key: "amd-dcm"
    operator: "Equal"
    value: "up"
    effect: "NoExecute"
```

Without this, NFD workers won't run on nodes with the `amd-dcm` taint, and those nodes won't receive AMD GPU feature labels.

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

The `imageRegistrySecret` flows from `DeviceConfig` → `Module.spec.imageRepoSecret` → module-loader pod `imagePullSecrets`, so KMM handles pull/push authentication automatically without any ServiceAccount patching.
